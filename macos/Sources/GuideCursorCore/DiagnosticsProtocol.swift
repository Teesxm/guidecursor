import Foundation

// Development diagnostics protocol (version 1). One request per connection, one JSON line each way.
//
//   request:  {"v":1,"cmd":"status"}            read-only snapshot
//             {"v":1,"cmd":"scan","selection":N} counts-only AX scan of the app already selected in GuideCursor;
//                                                "selection" (optional) must equal status.selected.selection_generation
//             {"v":1,"cmd":"self_check"}        counts-only AX scan of GuideCursor's own window (live, deterministic UI)
//             {"v":1,"cmd":"fixture"}           synthetic in-memory trees through this binary's scanner (no AX)
//   response: {"ok":true,...} or {"ok":false,"error":"<code>","session":"..."}
//
// Reports carry only codes, counts, timings and build/process identity: never the request text,
// window titles, control labels, document names, images or clipboard contents.

public enum DiagnosticsCommand: String, CaseIterable, Sendable {
    case status, scan, selfCheck = "self_check", fixture
}

public struct DiagnosticsRequest: Equatable, Sendable {
    public let command: DiagnosticsCommand
    public let selection: Int?
    public init(command: DiagnosticsCommand, selection: Int?) { self.command = command; self.selection = selection }
}

public enum DiagnosticsError: String, Error, Sendable {
    case tooLarge = "request_too_large"
    case malformed = "malformed_request"
    case unsupportedVersion = "unsupported_version"
    case unknownCommand = "unknown_command"
    case disabled = "diagnostics_disabled"
    case busy = "busy"
    case rateLimited = "rate_limited"
    case staleSelection = "stale_selection"
    case noSelection = "no_selected_app"
    case guidanceActive = "guidance_active"
    case timedOut = "timed_out"
    case userWorkActive = "user_work_active"     // Find controls, target validation or guidance is running
    case preempted = "preempted_by_user"         // the user started work while this scan was admitted
}

public enum DiagnosticsProtocol {
    public static let version = 1
    public static let maxRequestBytes = 1024
    private static let allowedKeys: Set<String> = ["v", "cmd", "selection"]

    public static func parse(_ data: Data) -> Result<DiagnosticsRequest, DiagnosticsError> {
        guard data.count <= maxRequestBytes else { return .failure(.tooLarge) }
        guard let object = try? JSONSerialization.jsonObject(with: data), let fields = object as? [String: Any],
              Set(fields.keys).isSubset(of: allowedKeys) else { return .failure(.malformed) }
        guard let version = integer(fields["v"]) else { return .failure(.malformed) }
        guard version == Self.version else { return .failure(.unsupportedVersion) }
        guard let name = fields["cmd"] as? String else { return .failure(.malformed) }
        guard let command = DiagnosticsCommand(rawValue: name) else { return .failure(.unknownCommand) }
        var selection: Int?
        if let raw = fields["selection"] {
            guard command == .scan, let value = integer(raw), value >= 0 else { return .failure(.malformed) }
            selection = value
        }
        return .success(DiagnosticsRequest(command: command, selection: selection))
    }

    /// JSON integers only: `true`/`false` bridge to NSNumber and would otherwise read as 1/0.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let int = value as? Int, Double(int) == number.doubleValue else { return nil }
        return int
    }

    public static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return ((try? encoder.encode(value)) ?? Data("{\"ok\":false,\"error\":\"encoding_failed\"}".utf8)) + Data("\n".utf8)
    }

    public struct ErrorResponse: Encodable { public let ok = false; public let error: String; public let session: String? }
    public static func error(_ error: DiagnosticsError, session: String?) -> Data {
        encode(ErrorResponse(error: error.rawValue, session: session))
    }
}

// MARK: Consent, request limits and live-work ownership

/// Cancellation flag shared with the accessibility queue. Set when the scan's reply can no longer be
/// used (user work started, selection changed, diagnostics turned off, or the caller stopped waiting).
public final class LiveScanTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public var isCancelled: Bool { lock.withLock { cancelled } }
    public func cancel() { lock.withLock { cancelled = true } }
}

/// One admitted request. Live AX commands carry a ticket and hold the single live-work reservation.
public struct Admission: Sendable, Equatable {
    public let id: Int
    public let session: String
    public let command: DiagnosticsCommand
    let userEpoch: Int
    let selectionEpoch: Int
    public let ticket: LiveScanTicket?
    public static func == (a: Admission, b: Admission) -> Bool { a.id == b.id }
}

/// Session consent, rate limits and live-work ownership. Pure; wrapped by `DiagnosticsCoordinator`.
public struct DiagnosticsGate: Sendable {
    public private(set) var session: String?
    public private(set) var enabledAt: Date?
    public private(set) var requests = 0
    /// AX work admitted and not yet finished on the queue. It outlives caller timeouts and sessions,
    /// so new live work waits for it instead of piling up behind it.
    public private(set) var reservation: Admission?
    public private(set) var userWorkActive = false
    private var nextID = 0
    private var lastLiveScan: Date?
    private var userEpoch = 0
    private var selectionEpoch = 0
    public static let minimumScanInterval: TimeInterval = 1

    public init() {}
    public var enabled: Bool { session != nil }

    /// Starts a new session with a fresh identifier; returns it.
    public mutating func enable(now: Date = Date()) -> String {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        session = id; enabledAt = now; requests = 0; lastLiveScan = nil
        return id
    }
    /// Ends the session. Any running scan is cancelled; its reply will be dropped.
    public mutating func disable() { session = nil; enabledAt = nil; reservation?.ticket?.cancel() }

    public mutating func admit(_ request: DiagnosticsRequest, now: Date = Date(), hasSelection: Bool,
                               selectionGeneration: Int, guiding: Bool) -> Result<Admission, DiagnosticsError> {
        guard let session else { return .failure(.disabled) }
        requests += 1; nextID += 1
        func admission(_ ticket: LiveScanTicket?) -> Admission {
            Admission(id: nextID, session: session, command: request.command, userEpoch: userEpoch, selectionEpoch: selectionEpoch, ticket: ticket)
        }
        switch request.command {
        case .status, .fixture: return .success(admission(nil))
        case .scan, .selfCheck:
            if request.command == .scan {
                guard hasSelection else { return .failure(.noSelection) }
                if let expected = request.selection, expected != selectionGeneration { return .failure(.staleSelection) }
            }
            // The AX queue is shared with the user's own work; never delay or interleave with it.
            guard !guiding else { return .failure(.guidanceActive) }
            guard !userWorkActive else { return .failure(.userWorkActive) }
            guard reservation == nil else { return .failure(.busy) }
            if let last = lastLiveScan, now.timeIntervalSince(last) < Self.minimumScanInterval { return .failure(.rateLimited) }
            let admitted = admission(LiveScanTicket())
            reservation = admitted; lastLiveScan = now
            return .success(admitted)
        }
    }

    /// Called when the admission's AX work has really ended. A stale admission never releases a newer one.
    public mutating func finishLiveWork(_ admission: Admission) {
        if reservation?.id == admission.id { reservation = nil }
    }

    /// Why a finished live result must not be published, if any.
    public func refusal(for admission: Admission) -> DiagnosticsError? {
        guard session == admission.session else { return .disabled }
        guard userEpoch == admission.userEpoch else { return .preempted }
        if admission.command == .scan, selectionEpoch != admission.selectionEpoch { return .staleSelection }
        return nil
    }

    /// The user's own Find/validation/guidance started or ended. Starting cancels admitted live work.
    public mutating func setUserWork(active: Bool) {
        guard active != userWorkActive else { return }
        userWorkActive = active
        if active { userEpoch += 1; reservation?.ticket?.cancel() }
    }

    public mutating func selectionChanged() {
        selectionEpoch += 1
        if reservation?.command == .scan { reservation?.ticket?.cancel() }
    }
}

/// Result of one live AX diagnostic (counts only).
public struct LiveScanOutcome: Sendable {
    public let report: ScanReport
    public let expectedOwnControlsFound: Int?
    public let expectedOwnControlsTotal: Int?
    public init(report: ScanReport, expectedOwnControlsFound: Int? = nil, expectedOwnControlsTotal: Int? = nil) {
        self.report = report; self.expectedOwnControlsFound = expectedOwnControlsFound; self.expectedOwnControlsTotal = expectedOwnControlsTotal
    }
}

/// Thread-safe owner of the gate, used by the app and by the lifecycle checks. Live work is started
/// through `runLive`, which ties completion to the admission rather than to whoever happens to finish.
public final class DiagnosticsCoordinator: @unchecked Sendable {
    public typealias LiveWork = @Sendable (LiveScanTicket, @escaping @Sendable (LiveScanOutcome?) -> Void) -> Void
    private let lock = NSLock()
    private var gate = DiagnosticsGate()
    private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) { self.clock = clock }

    public var session: String? { lock.withLock { gate.session } }
    public var enabledAt: Date? { lock.withLock { gate.enabledAt } }
    public var requests: Int { lock.withLock { gate.requests } }
    public var liveWorkPending: Bool { lock.withLock { gate.reservation != nil } }

    public func enable() -> String { lock.withLock { gate.enable(now: clock()) } }
    public func disable() { lock.withLock { gate.disable() } }
    public func setUserWork(active: Bool) { lock.withLock { gate.setUserWork(active: active) } }
    public func selectionChanged() { lock.withLock { gate.selectionChanged() } }
    public func admit(_ request: DiagnosticsRequest, hasSelection: Bool, selectionGeneration: Int, guiding: Bool) -> Result<Admission, DiagnosticsError> {
        lock.withLock { gate.admit(request, now: clock(), hasSelection: hasSelection, selectionGeneration: selectionGeneration, guiding: guiding) }
    }
    /// Releases a live admission whose work was never started.
    public func abandon(_ admission: Admission) { lock.withLock { gate.finishLiveWork(admission) } }

    /// Starts `work` with the admission's ticket. `work` must call its completion exactly once when the
    /// AX work has really ended (nil if it stopped because the ticket was cancelled). The caller gets an
    /// answer after at most `waitLimit`; the reservation stays until the work itself ends.
    public func runLive(_ admission: Admission, waitLimit: TimeInterval, work: @escaping LiveWork) async -> Result<LiveScanOutcome, DiagnosticsError> {
        guard let ticket = admission.ticket else { return .failure(.malformed) }
        let answered = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<LiveScanOutcome, DiagnosticsError>, Never>) in
            work(ticket) { [self] outcome in
                let refusal: DiagnosticsError? = lock.withLock {
                    gate.finishLiveWork(admission)
                    return gate.refusal(for: admission)
                }
                guard answered.claim() else { return }      // the caller already stopped waiting
                if let refusal { continuation.resume(returning: .failure(refusal)) }
                else if let outcome { continuation.resume(returning: .success(outcome)) }
                else { continuation.resume(returning: .failure(.preempted)) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, waitLimit) * 1_000_000_000))
                if answered.claim() { ticket.cancel(); continuation.resume(returning: .failure(.timedOut)) }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var done = false
        func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
    }
}

// MARK: Redacted reports

public enum DiagnosticsCodes {
    public static func diagnosis(_ diagnosis: Diagnosis) -> String {
        switch diagnosis {
        case .permissionMissing: return "permission_missing"
        case .appUnavailable: return "app_unavailable"
        case .noWindow: return "no_window"
        case .appNotResponding: return "app_not_responding"
        case .noExposedControls: return "no_exposed_controls"
        case .controlsNotFullyRead: return "controls_not_fully_read"
        case .unsearchableRequest: return "unsearchable_request"
        case .noMatch: return "no_match"
        case .modelChoseNone: return "model_chose_none"
        case .matches: return "matches"
        }
    }
    public static func fallback(_ decision: FallbackDecision) -> String {
        switch decision {
        case .notNeeded: return "not_needed"
        case .fixAccessFirst: return "fix_access_first"
        case .retryAccessibility: return "retry_accessibility"
        case .rephrase: return "rephrase"
        case .offerScreenImage: return "offer_screen_image"
        }
    }
}

/// Counts-only outcome of one scan. `evidence` keeps synthetic results apart from live AX observations.
public struct ScanReport: Codable, Equatable, Sendable {
    public enum Evidence: String, Codable, Sendable { case liveSelectedApp = "live_ax_selected_app", liveSelf = "live_ax_self", synthetic }
    public enum Trigger: String, Codable, Sendable { case userFind = "user_find", diagnostics }
    public let evidence: Evidence
    public let trigger: Trigger
    public let at: Date
    public let selectionGeneration: Int
    public let targetBundleId: String?
    public let window: String
    public let elementsRead: Int
    public let namedControls: Int
    public let unnamedControls: Int
    public let failedReads: Int
    public let limits: [String]
    public let milliseconds: Int
    public let requestPresent: Bool
    public let matches: Int?
    public let diagnosis: String
    public let fallback: String

    /// `request` is used only to decide the diagnosis and is never stored.
    public init(evidence: Evidence, trigger: Trigger, at: Date = Date(), selectionGeneration: Int, targetBundleId: String?,
                trusted: Bool, stats: ScanStats, request: String, matches: Int?) {
        self.evidence = evidence; self.trigger = trigger; self.at = at
        self.selectionGeneration = selectionGeneration; self.targetBundleId = targetBundleId
        window = stats.window.rawValue; elementsRead = stats.elementsRead; namedControls = stats.labelledControls
        unnamedControls = stats.unlabelledInteractive; failedReads = stats.failedReads
        limits = ScanLimit.allCases.filter(stats.limits.contains).map { $0.rawValue.replacingOccurrences(of: " ", with: "_") }
        milliseconds = Int((stats.seconds * 1000).rounded())
        let present = !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        requestPresent = present
        if present, let matches {
            let result = Diagnostics.diagnose(trusted: trusted, stats: stats, request: request, matches: matches)
            self.matches = matches; diagnosis = DiagnosticsCodes.diagnosis(result)
            fallback = DiagnosticsCodes.fallback(ScreenFallback.decide(result, stats: stats))
        } else {
            // Without a request only the access/window/scan outcome can be judged.
            let result = Diagnostics.diagnose(trusted: trusted, stats: stats, request: "x", matches: 1)
            self.matches = nil; diagnosis = result == .matches(1) ? "no_request" : DiagnosticsCodes.diagnosis(result)
            fallback = "not_evaluated"
        }
    }
}

// MARK: Guidance lifecycle

/// Observable guidance state. Engine flags only: they do not prove the user saw or heard anything.
public struct GuidanceHealth: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case idle, validating, guiding, pausedOtherApp = "paused_other_app" }
    public enum Refresh: String, Codable, Sendable { case ok, windowChanged = "window_changed", targetInvalid = "target_invalid", offScreen = "off_screen", noScreen = "no_screen" }
    public enum StopReason: String, Codable, Sendable {
        case user, newSearch = "new_search", appChanged = "app_changed", appClosed = "app_closed", clickedNearTarget = "clicked_near_target",
             windowChanged = "window_changed", targetInvalid = "target_invalid", offScreen = "off_screen", permissionRemoved = "permission_removed"
    }
    public private(set) var state: State = .idle
    public private(set) var refreshSuccesses = 0
    public private(set) var refreshFailures = 0
    public private(set) var lastRefresh: Refresh?
    public private(set) var lastRefreshAt: Date?
    public private(set) var lastStopReason: StopReason?
    public private(set) var guidanceStarts = 0

    public init() {}
    public mutating func validating() { state = .validating }
    public mutating func started() { state = .guiding; guidanceStarts += 1 }
    public mutating func paused() { if state == .guiding { state = .pausedOtherApp } }
    public mutating func refreshed(_ outcome: Refresh, at: Date = Date()) {
        lastRefresh = outcome; lastRefreshAt = at
        if outcome == .ok { refreshSuccesses += 1; if state == .pausedOtherApp { state = .guiding } } else { refreshFailures += 1 }
    }
    /// Records why an active or validating guidance session ended; stops while idle change nothing.
    public mutating func stopped(_ reason: StopReason) {
        guard state != .idle else { return }
        lastStopReason = reason; state = .idle
    }
}
