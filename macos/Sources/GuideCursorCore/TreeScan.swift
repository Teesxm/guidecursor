import CoreGraphics
import Foundation

/// Why an attribute read did not return a value. "Absent" (unsupported or no value) is normal
/// and is not a failure; these cases are operational problems that make a scan incomplete.
public enum ReadFailure: Equatable {
    case permission      // accessibility API disabled for this process
    case invalidElement  // element (or app) no longer exists
    case timeout         // app did not answer within the messaging timeout
    case other
}

public enum Read<T> {
    case value(T)
    case absent
    case failed(ReadFailure)
}

/// A bounded prefix of an array attribute together with the attribute's full length.
public struct Slice<E> {
    public let items: [E]
    public let total: Int
    public init(items: [E], total: Int) { self.items = items; self.total = total }
}

/// The accessibility reads the scanner needs. The live implementation wraps AXUIElement;
/// checks use an in-memory tree, so traversal and fallback policy are tested without permissions.
public protocol TreeReader {
    associatedtype Element
    associatedtype Key: Hashable
    func key(_ element: Element) -> Key
    func string(_ element: Element, _ attribute: String) -> Read<String>
    func bool(_ element: Element, _ attribute: String) -> Read<Bool>
    func element(_ element: Element, _ attribute: String) -> Read<Element>
    /// Must not transfer more than `max` elements.
    func elements(_ element: Element, _ attribute: String, max: Int) -> Read<Slice<Element>>
    func frame(_ element: Element) -> Read<CGRect>
}

public struct TreeScanResult<Element> {
    public var window: Element?
    public var windowStatus: WindowLookup
    public var nodes: [ControlNode] = []
    public var elements: [Element] = []
    public var limits: Set<ScanLimit> = []
    public var failedReads = 0
}

public struct TreeScanner<R: TreeReader> {
    public static var acceptedWindowSubroles: Set<String> { ["AXStandardWindow", "AXDialog", "AXSystemDialog", "AXFloatingWindow"] }
    /// Non-row children of a table are queued only when their list is this short; longer lists are the row list itself.
    public static var smallChildList: Int { 64 }

    let reader: R
    let clock: () -> Date
    let deadline: Date
    let maxElements: Int
    let maxDepth: Int
    private var result: TreeScanResult<R.Element>
    private var expired = false
    private var permissionLost = false

    public init(reader: R, budget: TimeInterval, maxElements: Int = 1200, maxDepth: Int = 30, clock: @escaping () -> Date = Date.init) {
        self.reader = reader; self.clock = clock; self.deadline = clock().addingTimeInterval(budget)
        self.maxElements = maxElements; self.maxDepth = maxDepth
        self.result = TreeScanResult(window: nil, windowStatus: .noWindow)
    }

    /// Checks the time budget before every reader call. A call that starts just before the
    /// deadline still runs to completion; on the live reader one call can be two native AX
    /// requests (frame: position + size; elements: count + copy), each limited by the messaging timeout.
    private mutating func read<T>(_ operation: (R) -> Read<T>) -> Read<T>? {
        guard !expired, clock() < deadline else { expired = true; result.limits.insert(.timeLimit); return nil }
        let value = operation(reader)
        if case .failed(let failure) = value {
            result.failedReads += 1
            if failure == .permission { permissionLost = true }
        }
        return value
    }

    // MARK: Window lookup

    /// Focused → main → listed windows, each validated the same way; then the frontmost sheet.
    /// Permission and app-gone errors stop immediately. Any other failed read is kept, so
    /// "no window" is reported only when every read answered normally.
    public mutating func lookupWindow(app: R.Element) -> TreeScanResult<R.Element> {
        var chosen: R.Element?
        var candidates: [R.Element] = []
        for attribute in ["AXFocusedWindow", "AXMainWindow", "AXWindows"] {
            if attribute == "AXWindows" {
                guard let list = read({ $0.elements(app, attribute, max: 32) }) else { return finish(nil, .notResponding) }
                switch list {
                case .value(let windows): candidates = windows.items
                case .failed(let failure): if let stop = Self.terminal(failure) { return finish(nil, stop) }; candidates = []
                case .absent: candidates = []
                }
            } else {
                guard let single = read({ $0.element(app, attribute) }) else { return finish(nil, .notResponding) }
                switch single {
                case .value(let window): candidates = [window]
                case .failed(let failure): if let stop = Self.terminal(failure) { return finish(nil, stop) }; candidates = []
                case .absent: candidates = []
                }
            }
            for window in candidates {
                guard let ok = acceptable(window) else { return finish(nil, .notResponding) }
                if permissionLost { return finish(nil, .permissionDenied) }
                if ok { chosen = window; break }
            }
            if chosen != nil { break }
        }
        guard var window = chosen else { return finish(nil, result.failedReads > 0 ? .notResponding : .noWindow) }
        for _ in 0..<4 {
            guard case .value(let sheets)? = read({ $0.elements(window, "AXSheets", max: 8) }), let sheet = sheets.items.last else { break }
            window = sheet
        }
        return finish(window, .found)
    }

    /// Failures reading the application element itself that make any fallback pointless.
    static func terminal(_ failure: ReadFailure) -> WindowLookup? {
        switch failure {
        case .permission: return .permissionDenied
        case .invalidElement: return .appUnavailable
        case .timeout, .other: return nil
        }
    }

    /// nil = budget expired. false = not a usable window, including when it could not be validated.
    private mutating func acceptable(_ window: R.Element) -> Bool? {
        guard let role = read({ $0.string(window, "AXRole") }) else { return nil }
        if case .value(let value) = role, value != "AXWindow" { return false }
        if case .failed = role { return false }
        guard let subrole = read({ $0.string(window, "AXSubrole") }) else { return nil }
        switch subrole {
        case .value(let value) where !Self.acceptedWindowSubroles.contains(value): return false
        case .failed: return false
        default: break
        }
        guard let minimized = read({ $0.bool(window, "AXMinimized") }) else { return nil }
        switch minimized {
        case .value(true), .failed: return false
        default: return true
        }
    }

    private mutating func finish(_ window: R.Element?, _ status: WindowLookup) -> TreeScanResult<R.Element> {
        result.window = window; result.windowStatus = status
        return result
    }

    // MARK: Traversal

    public mutating func scan(app: R.Element) -> TreeScanResult<R.Element> {
        let lookup = lookupWindow(app: app)
        guard let window = lookup.window else { return lookup }
        // `rows`: visible rows of the nearest table/outline ancestor that reports AXVisibleRows.
        // Any other AXRow in that subtree (via a short child list, a column or a group) is hidden.
        var stack: [(element: R.Element, parent: Int?, depth: Int, rows: Set<R.Key>?)] = [(window, nil, 0, nil)]
        var visited = Set<R.Key>()
        while let item = stack.popLast() {
            if visited.count >= maxElements { result.limits.insert(.elementLimit); break }
            let key = reader.key(item.element)
            guard visited.insert(key).inserted else { continue }
            guard item.depth < maxDepth else { result.limits.insert(.depthLimit); continue }
            let hiddenRow = item.rows.map { !$0.contains(key) } ?? false
            guard let id = readNode(item.element, parent: item.parent, skipRow: hiddenRow) else {
                if expired { break } else { continue }
            }
            let role = result.nodes[id].role
            let room = max(0, maxElements - visited.count - stack.count)
            guard let (children, visibleRows) = readChildren(item.element, role: role, room: room) else { break }
            // A table/outline sets the context for its subtree (nil when visibility is unsupported).
            let rows = role == "AXOutline" || role == "AXTable" ? visibleRows : item.rows
            stack.append(contentsOf: children.reversed().map { ($0, id, item.depth + 1, rows) })
        }
        if permissionLost { result.windowStatus = .permissionDenied }
        return result
    }

    /// Returns the new node id, or nil when the role could not be read, the element is a hidden
    /// row (`skipRow`), or the budget expired.
    private mutating func readNode(_ element: R.Element, parent: Int?, skipRow: Bool) -> Int? {
        guard case .value(let role)? = read({ $0.string(element, "AXRole") }) else { return nil }
        if skipRow && role == "AXRow" { return nil }
        func text(_ read: Read<String>?) -> String? { if case .value(let s)? = read { return s }; return nil }
        let title = text(read { $0.string(element, "AXTitle") })
        let description = text(read { $0.string(element, "AXDescription") })
        let help = text(read { $0.string(element, "AXHelp") })
        // Static text only; editable field values are never read.
        let staticText = role == "AXStaticText" ? text(read { $0.string(element, "AXValue") }) : nil
        var frame: CGRect?
        if case .value(let rect)? = read({ $0.frame(element) }) { frame = rect }
        var enabled = true
        if case .value(false)? = read({ $0.bool(element, "AXEnabled") }) { enabled = false }
        guard !expired else { return nil }
        let id = result.nodes.count
        result.nodes.append(ControlNode(id: id, parent: parent, role: role, title: title, description: description,
                                        help: help, staticText: staticText, frame: frame, enabled: enabled))
        result.elements.append(element)
        return id
    }

    /// Bounded read of an array attribute; records truncation as an element limit.
    private mutating func list(_ element: R.Element, _ attribute: String, room: Int) -> Read<[R.Element]>? {
        guard let read = read({ $0.elements(element, attribute, max: room) }) else { return nil }
        switch read {
        case .value(let slice):
            if slice.total > slice.items.count { result.limits.insert(.elementLimit) }
            return .value(slice.items)
        case .absent: return .absent
        case .failed(let failure): return .failed(failure)
        }
    }

    /// Children to queue (deduplicated) and, for a table/outline that supports AXVisibleRows,
    /// the authoritative visible-row set. nil = budget expired.
    private mutating func readChildren(_ element: R.Element, role: String, room: Int) -> ([R.Element], Set<R.Key>?)? {
        guard let visible = list(element, "AXVisibleChildren", room: room) else { return nil }
        var visibleChildren: [R.Element] = []
        if case .value(let items) = visible { visibleChildren = items }

        guard role == "AXOutline" || role == "AXTable" else {
            if !visibleChildren.isEmpty { return (visibleChildren, nil) }
            guard let all = list(element, "AXChildren", room: room) else { return nil }
            if case .value(let items) = all { return (items, nil) }
            return ([], nil)
        }

        // Rows: visible rows when the attribute is supported (an empty list is respected);
        // otherwise a bounded prefix of AXRows. Failed reads are counted, then fall back.
        var rows: [R.Element] = []
        var rowsKnown = false
        var visibleSet: Set<R.Key>?
        guard let visibleRows = list(element, "AXVisibleRows", room: room) else { return nil }
        if case .value(let items) = visibleRows {
            rows = items; rowsKnown = true; visibleSet = Set(items.map(reader.key))
        } else {
            guard let allRows = list(element, "AXRows", room: room) else { return nil }
            if case .value(let items) = allRows { rows = items; rowsKnown = true }
        }
        var children: [R.Element] = []
        guard let header = read({ $0.element(element, "AXHeader") }) else { return nil }
        if case .value(let item) = header { children.append(item) }
        children += rows

        // Other children (columns, scroll bars, custom parts). A short AXChildren list may still
        // contain rows; with supported AXVisibleRows, hidden ones are skipped in the traversal.
        if !visibleChildren.isEmpty {
            children += visibleChildren
        } else if rowsKnown {
            guard let probe = read({ $0.elements(element, "AXChildren", max: Self.smallChildList) }) else { return nil }
            if case .value(let slice) = probe, slice.total <= Self.smallChildList { children += slice.items }
        } else {
            guard let all = list(element, "AXChildren", room: max(0, room - children.count)) else { return nil }
            if case .value(let items) = all { children += items }
        }
        var seen = Set<R.Key>()
        return (children.filter { seen.insert(reader.key($0)).inserted }, visibleSet)
    }
}
