import Foundation

/// Outcome of looking up the window to scan. Derived from accessibility error codes, not screen content.
public enum WindowLookup: String, Equatable {
    case found
    case noWindow          // app answered, but has no open/focused window
    case notResponding     // app did not answer in time
    case permissionDenied  // macOS refused accessibility access
    case appUnavailable    // app quit or its process is no longer valid
}

/// Why a traversal stopped before reading the whole window.
public enum ScanLimit: String, CaseIterable, Equatable {
    case elementLimit = "element limit"
    case timeLimit = "time limit"
    case depthLimit = "depth limit"
}

/// Counts-only description of a scan. Contains no labels, values or other on-screen text,
/// so it can be shown or copied for troubleshooting without exposing private content.
public struct ScanStats: Equatable {
    public var window: WindowLookup
    public var elementsRead: Int
    public var labelledControls: Int
    public var unlabelledInteractive: Int
    public var failedReads: Int
    public var limits: Set<ScanLimit>
    public var labelledRoles: [String: Int]
    public var seconds: Double

    public init(window: WindowLookup, elementsRead: Int = 0, labelledControls: Int = 0,
                unlabelledInteractive: Int = 0, failedReads: Int = 0, limits: Set<ScanLimit> = [],
                labelledRoles: [String: Int] = [:], seconds: Double = 0) {
        self.window = window; self.elementsRead = elementsRead; self.labelledControls = labelledControls
        self.unlabelledInteractive = unlabelledInteractive; self.failedReads = failedReads
        self.limits = limits; self.labelledRoles = labelledRoles; self.seconds = seconds
    }
    public var incomplete: Bool { !limits.isEmpty || failedReads > 0 }

    /// Builds counts from a traversed tree and its indexed candidates. Only roles and counts are kept.
    public static func from(nodes: [ControlNode], indexed: [IndexedControl], limits: Set<ScanLimit>,
                            failedReads: Int, seconds: Double) -> ScanStats {
        ScanStats(window: .found, elementsRead: nodes.count, labelledControls: indexed.count,
                  unlabelledInteractive: ControlIndex.interactiveIDs(in: nodes).subtracting(indexed.map(\.nodeID)).count,
                  failedReads: failedReads, limits: limits,
                  labelledRoles: Dictionary(grouping: indexed, by: \.role).mapValues(\.count), seconds: seconds)
    }
}

public enum Diagnosis: Equatable {
    case permissionMissing
    case appUnavailable
    case noWindow
    case appNotResponding
    case noExposedControls(unlabelled: Int)
    case controlsNotFullyRead
    case unsearchableRequest
    case noMatch(controls: Int)
    case modelChoseNone(controls: Int)
    case matches(Int)
}

public enum Diagnostics {
    /// Ordered from most to least fundamental, so the user is told the first thing to fix.
    public static func diagnose(trusted: Bool, stats: ScanStats, request: String, matches: Int, usedModel: Bool = false) -> Diagnosis {
        guard trusted, stats.window != .permissionDenied else { return .permissionMissing }
        switch stats.window {
        case .appUnavailable: return .appUnavailable
        case .noWindow: return .noWindow
        case .notResponding: return .appNotResponding
        case .found, .permissionDenied: break
        }
        // Only claim the app exposes nothing when the whole window was actually read.
        if stats.labelledControls == 0 {
            return stats.incomplete ? .controlsNotFullyRead : .noExposedControls(unlabelled: stats.unlabelledInteractive)
        }
        if matches > 0 { return .matches(matches) }
        if usedModel { return .modelChoseNone(controls: stats.labelledControls) }
        if Guidance.terms(request).isEmpty { return .unsearchableRequest }
        return .noMatch(controls: stats.labelledControls)
    }

    public static func message(_ diagnosis: Diagnosis, appName: String, stats: ScanStats) -> String {
        let base: String
        switch diagnosis {
        case .permissionMissing:
            return "Accessibility permission is missing or out of date. Enable GuideCursor in System Settings → Privacy & Security → Accessibility. After a rebuild, remove and re-add it, then retry."
        case .appUnavailable:
            return "\(appName) is no longer running. Select Refresh and choose an open app."
        case .noWindow:
            return "\(appName) has no open window to read. Open or un-minimise a window in \(appName), then retry."
        case .appNotResponding:
            return "\(appName) did not respond to accessibility requests in time. Wait until it is idle, then retry."
        case .noExposedControls(let unlabelled):
            base = unlabelled > 0
                ? "\(appName)'s window exposes \(unlabelled) controls, but none have readable names. This app may need the future screen-recognition fallback."
                : "\(appName)'s window exposes no controls through macOS accessibility. This app may need the future screen-recognition fallback."
        case .controlsNotFullyRead:
            return "GuideCursor could not fully read \(appName)'s window, and no named controls were read before it stopped. Controls may still exist. Wait until \(appName) is idle and retry. " + incompleteNote(stats)
        case .unsearchableRequest:
            return "Your request has no searchable words. Type the control's visible name, for example “Downloads” or “Search”."
        case .noMatch(let controls):
            base = "No match among \(controls) named controls in \(appName). Try the exact visible name, or bring the window or tab that shows it to the front."
        case .modelChoseNone(let controls):
            base = "The local model suggested none of the \(controls) named controls. Try label search or rephrase."
        case .matches(let count):
            base = "Found \(count) matching \(count == 1 ? "control" : "controls"). Choose the intended one below."
        }
        guard stats.incomplete else { return base }
        return base + " " + incompleteNote(stats)
    }

    public static func incompleteNote(_ stats: ScanStats) -> String {
        var reasons = ScanLimit.allCases.filter(stats.limits.contains).map(\.rawValue)
        if stats.failedReads > 0 { reasons.append("\(stats.failedReads) failed reads") }
        return "Part of the window was not read (\(reasons.joined(separator: ", "))), so the control may exist but was missed. Closing other tabs or panes, or using a smaller window, can help."
    }

    /// One-line, counts-only summary safe to display or copy. Never includes labels.
    public static func summary(_ stats: ScanStats, appName: String) -> String {
        let roles = stats.labelledRoles.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(6).map { "\($0.key.replacingOccurrences(of: "AX", with: "")) \($0.value)" }.joined(separator: ", ")
        var parts = ["\(appName): window \(stats.window.rawValue)",
                     "\(stats.elementsRead) elements read",
                     "\(stats.labelledControls) named controls" + (roles.isEmpty ? "" : " (\(roles))"),
                     "\(stats.unlabelledInteractive) unnamed",
                     String(format: "%.1f s", stats.seconds)]
        let limits = ScanLimit.allCases.filter(stats.limits.contains).map(\.rawValue)
        if !limits.isEmpty { parts.append("stopped: " + limits.joined(separator: ", ")) }
        if stats.failedReads > 0 { parts.append("\(stats.failedReads) failed reads") }
        return parts.joined(separator: " · ")
    }
}
