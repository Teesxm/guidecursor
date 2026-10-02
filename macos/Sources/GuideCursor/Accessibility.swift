import AppKit
import ApplicationServices
import GuideCursorCore

struct Control: Identifiable {
    let id: Int
    let label: String
    let role: String
    let region: String
    let element: AXUIElement
    let rect: CGRect
}
struct Scan {
    let controls: [Control]
    let window: AXUIElement?
    let stats: ScanStats
}
/// Identity for AXUIElements using CFEqual, so distinct elements never collide.
struct ElementKey: Hashable {
    let element: AXUIElement
    static func == (a: ElementKey, b: ElementKey) -> Bool { CFEqual(a.element, b.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}
/// Live accessibility reads that keep the AXError, so unsupported attributes are not confused with failures.
struct LiveReader: TreeReader {
    static func classify(_ error: AXError) -> Read<Never>? {
        switch error {
        case .success: return nil
        case .attributeUnsupported, .noValue, .parameterizedAttributeUnsupported, .notImplemented: return .absent
        case .apiDisabled: return .failed(.permission)
        case .invalidUIElement: return .failed(.invalidElement)
        case .cannotComplete: return .failed(.timeout)
        default: return .failed(.other)
        }
    }
    private func raw(_ element: AXUIElement, _ attribute: String) -> Read<CFTypeRef> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if let problem = Self.classify(error) { return problem.map() }
        guard let value else { return .absent }
        return .value(value)
    }
    func key(_ element: AXUIElement) -> ElementKey { ElementKey(element: element) }
    func string(_ element: AXUIElement, _ attribute: String) -> Read<String> {
        raw(element, attribute).flatMap { $0 as? String }
    }
    func bool(_ element: AXUIElement, _ attribute: String) -> Read<Bool> {
        raw(element, attribute).flatMap { $0 as? Bool }
    }
    func element(_ element: AXUIElement, _ attribute: String) -> Read<AXUIElement> {
        raw(element, attribute).flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }
    func elements(_ element: AXUIElement, _ attribute: String, max: Int) -> Read<Slice<AXUIElement>> {
        var count: CFIndex = 0
        let countError = AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)
        let countKnown = countError == .success
        if !countKnown, countError != .illegalArgument, countError != .failure, let problem = Self.classify(countError) { return problem.map() }
        guard max > 0 else { return .value(Slice(items: [], total: countKnown ? count : 1)) }
        if countKnown && count == 0 { return .value(Slice(items: [], total: 0)) }
        // Copies at most `max` entries rather than the whole (possibly huge) array. If the count
        // itself was refused, a full prefix is treated as possibly truncated.
        var values: CFArray?
        let error = AXUIElementCopyAttributeValues(element, attribute as CFString, 0, countKnown ? Swift.min(count, max) : max, &values)
        if let problem = Self.classify(error) { return problem.map() }
        let items = (values as? [AXUIElement]) ?? []
        return .value(Slice(items: items, total: countKnown ? count : items.count == max ? max + 1 : items.count))
    }
    func frame(_ element: AXUIElement) -> Read<CGRect> {
        let position = raw(element, kAXPositionAttribute), size = raw(element, kAXSizeAttribute)
        guard case .value(let p) = position else { return position.map() }
        guard case .value(let s) = size else { return size.map() }
        guard CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return .absent }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &extent),
              point.x.isFinite, point.y.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return .absent }
        return .value(CGRect(origin: point, size: extent))
    }
}
private extension Read {
    /// Re-types a non-value result; a value maps to `.absent` (only used on non-value paths).
    func map<U>() -> Read<U> {
        switch self {
        case .value: return .absent
        case .absent: return .absent
        case .failed(let failure): return .failed(failure)
        }
    }
    func flatMap<U>(_ transform: (T) -> U?) -> Read<U> {
        guard case .value(let value) = self else { return map() }
        return transform(value).map { .value($0) } ?? .absent
    }
}
/// Call only from the background accessibility queue: every function here may block on another app.
enum Accessibility {
    /// A global per-request timeout keeps an unresponsive app from stalling each read for macOS's default ~6 s.
    private static let timeoutConfigured: Void = { AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3) }()
    static func rect(_ element: AXUIElement) -> CGRect? {
        if case .value(let rect) = LiveReader().frame(element) { return rect }
        return nil
    }
    static func enabled(_ element: AXUIElement) -> Bool {
        if case .value(false) = LiveReader().bool(element, kAXEnabledAttribute) { return false }
        return true
    }
    /// Same validated fallback as a scan, with a short budget for use during guidance.
    static func focusedWindow(_ pid: pid_t) -> AXUIElement? {
        _ = timeoutConfigured
        var scanner = TreeScanner(reader: LiveReader(), budget: 1)
        return scanner.lookupWindow(app: AXUIElementCreateApplication(pid)).window
    }
    static func scan(pid: pid_t) -> Scan {
        _ = timeoutConfigured
        let started = Date()
        var scanner = TreeScanner(reader: LiveReader(), budget: 3)
        let tree = scanner.scan(app: AXUIElementCreateApplication(pid))
        guard let window = tree.window, tree.windowStatus == .found else {
            var stats = ScanStats(window: tree.windowStatus, failedReads: tree.failedReads, limits: tree.limits)
            stats.seconds = Date().timeIntervalSince(started)
            return Scan(controls: [], window: nil, stats: stats)
        }
        // The window (or sheet) is node 0, so its geometry was read within the scan budget.
        let windowFrame = tree.nodes.first?.frame
        let indexed = ControlIndex.candidates(in: tree.nodes)
        let controls = indexed.map { candidate in
            Control(id: candidate.nodeID, label: candidate.label, role: candidate.role,
                    region: windowFrame.map { Guidance.region(target: candidate.frame, window: $0) } ?? "position unknown",
                    element: tree.elements[candidate.nodeID], rect: candidate.frame)
        }
        let stats = ScanStats.from(nodes: tree.nodes, indexed: indexed, limits: tree.limits, failedReads: tree.failedReads,
                                   seconds: Date().timeIntervalSince(started))
        return Scan(controls: controls, window: window, stats: stats)
    }
}
