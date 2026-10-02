import Darwin
import Foundation

public enum DiagnosticsPaths {
    /// Per-user location; the directory is created 0700 and the socket 0600.
    public static var defaultSocket: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("nl.guidecursor.prototype/diagnostics/diag.sock").path
    }
}

public enum DiagnosticsSocketError: Error, Equatable {
    case pathTooLong
    case insecureDirectory      // not a real directory owned by this user with mode 0700
    case occupied               // another process is already serving this socket
    case notASocket             // something else exists at the socket path
    case system(String, Int32)
}

private func makeAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw DiagnosticsSocketError.pathTooLong }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: bytes); raw[bytes.count] = 0
    }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return address
}

private func withAddress<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
}

private func setTimeouts(_ fd: Int32, seconds: TimeInterval) {
    var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
}

private func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let written = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
            if written <= 0 { return }
            offset += written
        }
    }
}

/// One accepted socket. The descriptor is closed exactly once, by whichever owner finishes last
/// (the reading thread, or the response task it hands over to), never by the server. `cut()` only
/// shuts the socket down, so a late task can never write to or close a descriptor number that has
/// already been closed and reused.
final class Connection: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32
    private var isCut = false
    init(_ fd: Int32) { self.fd = fd }

    /// Server stop: disconnect the peer immediately; no reply will be written.
    func cut() { lock.withLock { isCut = true; if fd >= 0 { shutdown(fd, SHUT_RDWR) } } }
    var wasCut: Bool { lock.withLock { isCut } }
    /// The descriptor for reading; only the current owner calls this, before `close`.
    var descriptor: Int32 { lock.withLock { fd } }

    /// Writes the reply unless cut, then closes. Safe to call once from the owner.
    func finish(replying data: Data?) {
        lock.withLock {
            guard fd >= 0 else { return }
            if let data, !isCut { writeAll(fd, data) }
            shutdown(fd, SHUT_RDWR); close(fd); fd = -1
        }
    }
    deinit { if fd >= 0 { close(fd) } }
}

/// Minimal local server: one request line per connection, answered by `handler`.
/// Only connections from the same user are served; nothing listens on the network.
public final class DiagnosticsServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data) async -> Data
    public let path: String
    private let handler: Handler
    private let maxClients: Int
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var connections: [ObjectIdentifier: Connection] = [:]
    private var running = false
    /// Device and inode of the socket file this instance bound. Only that exact file is ever unlinked,
    /// so a refused or stopped instance can never remove another listener's endpoint at the same path.
    private var boundFile: (device: dev_t, inode: ino_t)?
    private let queue = DispatchQueue(label: "guidecursor.diagnostics.accept")

    public init(path: String, maxClients: Int = 2, timeout: TimeInterval = 2, handler: @escaping Handler) {
        self.path = path; self.maxClients = maxClients; self.timeout = timeout; self.handler = handler
    }
    deinit { stop() }

    public func start() throws {
        try Self.prepareDirectory((path as NSString).deletingLastPathComponent)
        try Self.removeStaleSocket(path)
        var address = try makeAddress(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DiagnosticsSocketError.system("socket", errno) }
        guard withAddress(&address, { bind(fd, $0, $1) }) == 0 else { let e = errno; close(fd); throw DiagnosticsSocketError.system("bind", e) }
        // The 0700 directory already keeps other users out; the socket itself is also owner-only.
        var bound = stat()
        guard lstat(path, &bound) == 0 else { let e = errno; close(fd); throw DiagnosticsSocketError.system("lstat", e) }
        let identity = (device: bound.st_dev, inode: bound.st_ino)
        guard chmod(path, 0o600) == 0, listen(fd, 4) == 0 else {
            let e = errno; close(fd); Self.unlinkIfSame(path, identity); throw DiagnosticsSocketError.system("listen", e)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.setCancelHandler { close(fd) }
        lock.withLock { listenFD = fd; self.source = source; running = true; boundFile = identity }
        source.resume()
    }

    /// Stops listening immediately, removes the socket and disconnects every open connection.
    /// Each connection's descriptor is then closed by its current owner, even if this server is released.
    /// Idempotent: an instance that never started, or already stopped, does nothing.
    public func stop() {
        let owned: (connections: [Connection], file: (device: dev_t, inode: ino_t))? = lock.withLock {
            guard running, let file = boundFile else { return nil }
            running = false; boundFile = nil
            source?.cancel(); source = nil; listenFD = -1
            defer { connections.removeAll() }
            return (Array(connections.values), file)
        }
        guard let owned else { return }
        owned.connections.forEach { $0.cut() }
        Self.unlinkIfSame(path, owned.file)
    }

    /// Removes `path` only if it is still the socket file identified by `file`. The check and unlink are
    /// not atomic; the window is tiny and limited to this user's private 0700 directory.
    private static func unlinkIfSame(_ path: String, _ file: (device: dev_t, inode: ino_t)) {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_dev == file.device, info.st_ino == file.inode, info.st_uid == getuid() else { return }
        unlink(path)
    }

    public var isRunning: Bool { lock.withLock { running } }
    /// Connections currently tracked by this server (for tests and status).
    public var openConnections: Int { lock.withLock { connections.count } }

    private func acceptOne() {
        let fd = lock.withLock { listenFD }
        guard fd >= 0 else { return }
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        let connection = Connection(client)   // owns the descriptor from here on
        var uid: uid_t = 0, gid: gid_t = 0
        let admitted = getpeereid(client, &uid, &gid) == 0 && uid == getuid() && lock.withLock { () -> Bool in
            guard running, connections.count < maxClients else { return false }
            connections[ObjectIdentifier(connection)] = connection; return true
        }
        guard admitted else { connection.finish(replying: nil); return }
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        setTimeouts(client, seconds: timeout)
        // The reading thread and the response task hold the connection, not the server.
        let handler = handler
        let forget: @Sendable () -> Void = { [weak self] in self?.forget(connection) }
        DispatchQueue.global(qos: .utility).async { Self.serve(connection, handler: handler, done: forget) }
    }

    private func forget(_ connection: Connection) { lock.withLock { _ = connections.removeValue(forKey: ObjectIdentifier(connection)) } }

    private static func serve(_ connection: Connection, handler: @escaping Handler, done: @escaping @Sendable () -> Void) {
        let fd = connection.descriptor
        var data = Data(), buffer = [UInt8](repeating: 0, count: 256)
        var tooLarge = false
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
            if data.count > DiagnosticsProtocol.maxRequestBytes { tooLarge = true; break }
            if buffer[0..<count].contains(UInt8(ascii: "\n")) { break }
        }
        // Cut while reading, or nothing usable: close without calling the handler.
        if connection.wasCut || (data.isEmpty && !tooLarge) { connection.finish(replying: nil); done(); return }
        if tooLarge { connection.finish(replying: DiagnosticsProtocol.error(.tooLarge, session: nil)); done(); return }
        let line = data.split(separator: UInt8(ascii: "\n"), maxSplits: 1, omittingEmptySubsequences: false).first.map { Data($0) } ?? data
        Task {
            let response = await handler(line)
            connection.finish(replying: response)   // no write if cut meanwhile
            done()
        }
    }

    static func prepareDirectory(_ directory: String) throws {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else { throw DiagnosticsSocketError.insecureDirectory }
    }

    static func removeStaleSocket(_ path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid() else { throw DiagnosticsSocketError.notASocket }
        // A socket that still accepts connections belongs to a running GuideCursor; leave it alone.
        if (try? DiagnosticsClient.connect(path, timeout: 0.5)).map({ close($0); return true }) == true { throw DiagnosticsSocketError.occupied }
        unlink(path)
    }
}

public enum DiagnosticsClient {
    static func connect(_ path: String, timeout: TimeInterval) throws -> Int32 {
        var address = try makeAddress(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DiagnosticsSocketError.system("socket", errno) }
        setTimeouts(fd, seconds: timeout)
        guard withAddress(&address, { Darwin.connect(fd, $0, $1) }) == 0 else { let e = errno; close(fd); throw DiagnosticsSocketError.system("connect", e) }
        return fd
    }

    /// Sends one request line and returns the response line.
    public static func send(_ request: Data, path: String, timeout: TimeInterval = 15) throws -> Data {
        let fd = try connect(path, timeout: timeout)
        defer { close(fd) }
        writeAll(fd, request.last == UInt8(ascii: "\n") ? request : request + Data("\n".utf8))
        var response = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            response.append(contentsOf: buffer[0..<count])
        }
        return response
    }
}
