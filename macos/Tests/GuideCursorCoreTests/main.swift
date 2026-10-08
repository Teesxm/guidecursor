import CoreGraphics
import Foundation
import GuideCursorCore
var assertions = 0
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    assertions += 1
    guard actual == expected else { fatalError("Expected \(expected), got \(actual)", file: file, line: line) }
}

/// In-memory accessibility tree. Missing attributes read as unsupported; `.fail` simulates an operational error.
enum FakeValue { case string(String), bool(Bool), element(Int), elements([Int]), frame(CGRect), fail(ReadFailure) }
final class FakeTree: TreeReader {
    var attributes: [Int: [String: FakeValue]]
    var reads: [String] = []
    var transferred = 0
    init(_ attributes: [Int: [String: FakeValue]]) { self.attributes = attributes }
    func key(_ element: Int) -> Int { element }
    private func get(_ element: Int, _ attribute: String) -> FakeValue? { reads.append("\(element).\(attribute)"); return attributes[element]?[attribute] }
    func string(_ element: Int, _ attribute: String) -> Read<String> {
        switch get(element, attribute) { case .string(let v)?: return .value(v); case .fail(let f)?: return .failed(f); default: return .absent }
    }
    func bool(_ element: Int, _ attribute: String) -> Read<Bool> {
        switch get(element, attribute) { case .bool(let v)?: return .value(v); case .fail(let f)?: return .failed(f); default: return .absent }
    }
    func element(_ element: Int, _ attribute: String) -> Read<Int> {
        switch get(element, attribute) { case .element(let v)?: return .value(v); case .fail(let f)?: return .failed(f); default: return .absent }
    }
    func elements(_ element: Int, _ attribute: String, max: Int) -> Read<Slice<Int>> {
        switch get(element, attribute) {
        case .elements(let v)?: let items = Array(v.prefix(max)); transferred += items.count; return .value(Slice(items: items, total: v.count))
        case .fail(let f)?: return .failed(f)
        default: return .absent
        }
    }
    func frame(_ element: Int) -> Read<CGRect> {
        switch get(element, "frame") { case .frame(let v)?: return .value(v); case .fail(let f)?: return .failed(f); default: return .absent }
    }
}
let app = 100
let box = CGRect(x: 10, y: 10, width: 100, height: 20)
func window(children: [Int], extra: [String: FakeValue] = [:]) -> [String: FakeValue] {
    ["AXRole": .string("AXWindow"), "AXSubrole": .string("AXStandardWindow"), "frame": .frame(CGRect(x: 0, y: 0, width: 800, height: 600)),
     "AXChildren": .elements(children)].merging(extra) { $1 }
}
func row(_ child: Int) -> [String: FakeValue] { ["AXRole": .string("AXRow"), "frame": .frame(box), "AXChildren": .elements([child])] }
func text(_ value: String) -> [String: FakeValue] { ["AXRole": .string("AXStaticText"), "AXValue": .string(value)] }
func scan(_ tree: FakeTree, budget: TimeInterval = 3, maxElements: Int = 1200, clock: @escaping () -> Date = Date.init) -> (TreeScanResult<Int>, ScanStats) {
    var scanner = TreeScanner(reader: tree, budget: budget, maxElements: maxElements, clock: clock)
    let result = scanner.scan(app: app)
    let stats = result.windowStatus == .found
        ? ScanStats.from(nodes: result.nodes, indexed: ControlIndex.candidates(in: result.nodes), limits: result.limits, failedReads: result.failedReads, seconds: 0)
        : ScanStats(window: result.windowStatus, failedReads: result.failedReads, limits: result.limits)
    return (result, stats)
}

func failure<T>(_ result: Result<T, DiagnosticsError>) -> DiagnosticsError? { if case .failure(let e) = result { return e }; return nil }
/// Live diagnostic work held suspended until the test completes it, like a scan waiting on the AX queue.
final class SuspendedWork: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (LiveScanOutcome?) -> Void)?
    private var ticket: LiveScanTicket?
    var work: DiagnosticsCoordinator.LiveWork { { ticket, done in self.lock.withLock { self.ticket = ticket; self.completion = done } } }
    var started: Bool { lock.withLock { completion != nil } }
    var cancelled: Bool { lock.withLock { ticket?.isCancelled ?? false } }
    func complete(_ outcome: LiveScanOutcome?) { let done = lock.withLock { completion }; done?(outcome) }
}
final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var value = Date(timeIntervalSince1970: 5000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}
let sampleOutcome = LiveScanOutcome(report: ScanReport(evidence: .liveSelectedApp, trigger: .diagnostics, selectionGeneration: 0, targetBundleId: nil,
                                                       trusted: true, stats: ScanStats(window: .found, labelledControls: 1), request: "x", matches: 1))
func waitUntil(_ condition: () -> Bool, seconds: TimeInterval = 3) async {
    let deadline = Date() + seconds
    while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
}
/// Counts handler entries/exits so tests can act while a request is provably in progress.
final class HandlerProbe: @unchecked Sendable {
    private let lock = NSLock(); private var inCount = 0, outCount = 0
    func enter() { lock.withLock { inCount += 1 } }
    func exit() { lock.withLock { outCount += 1 } }
    var entered: Int { lock.withLock { inCount } }
    var exited: Int { lock.withLock { outCount } }
}
func openDescriptors() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1 }
/// Raw client that connects and sends a partial line, to hold a connection in the server's read phase.
func connectRaw(_ path: String) -> Int32 {
    var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in let bytes = Array(path.utf8); raw.copyBytes(from: bytes); raw[bytes.count] = 0 }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    return fd
}
final class GuidanceTests {
    let target = CGRect(x: 100, y: 100, width: 40, height: 30)
    func testInsideTargetWaitsForUser() { XCTAssertEqual(Guidance.direction(pointer: CGPoint(x: 110, y: 110), target: target), "On target. Click when ready.") }
    func testTopLeftCoordinates() {
        XCTAssertEqual(Guidance.direction(pointer: CGPoint(x: 140, y: 110), target: target), "On target. Click when ready.")
        XCTAssertEqual(Guidance.direction(pointer: CGPoint(x: 110, y: 50), target: target), "Move down")
        XCTAssertEqual(Guidance.direction(pointer: CGPoint(x: 180, y: 110), target: target), "Move left")
        XCTAssertEqual(Guidance.direction(pointer: CGPoint(x: 50, y: 50), target: target), "Move down and right")
    }
    func testDisplayConversionIncludingNegativeOrigin() {
        XCTAssertEqual(Guidance.appKitRect(CGRect(x: -500, y: -100, width: 60, height: 40), primaryHeight: 900), CGRect(x: -500, y: 960, width: 60, height: 40))
    }
    func testRegionInMovedWindow() {
        let window = CGRect(x: -800, y: 100, width: 600, height: 600)
        XCTAssertEqual(Guidance.region(target: CGRect(x: -780, y: 120, width: 20, height: 20), window: window), "upper left area")
        XCTAssertEqual(Guidance.region(target: CGRect(x: -250, y: 630, width: 20, height: 20), window: window), "lower right area")
    }
    func testNoMatchAndNaturalRequest() {
        XCTAssertEqual(Guidance.score(request: "help me find the search button", label: "Search"), 15)
        XCTAssertEqual(Guidance.score(request: "download", label: "Close"), 0)
        XCTAssertEqual(Guidance.score(request: "help me", label: "Search"), 0)
    }
    func testModelCannotInventControlIDs() {
        XCTAssertEqual(Guidance.validatedIDs([2, 900, 2, -1, 3], allowed: [2, 3]), [2, 3])
    }
    func testUnlabelledOutlineRowUsesVisibleChildText() {
        let nodes = [
            ControlNode(id: 0, parent: nil, role: "AXWindow"),
            ControlNode(id: 1, parent: 0, role: "AXOutline"),
            ControlNode(id: 2, parent: 1, role: "AXRow", frame: CGRect(x: 12, y: 350, width: 180, height: 24)),
            ControlNode(id: 3, parent: 2, role: "AXCell", frame: CGRect(x: 12, y: 350, width: 180, height: 24)),
            ControlNode(id: 4, parent: 3, role: "AXStaticText", staticText: "Downloads", frame: CGRect(x: 42, y: 353, width: 82, height: 18))
        ]
        let result = ControlIndex.candidates(in: nodes)
        XCTAssertEqual(result.map(\.nodeID), [2])
        XCTAssertEqual(result.map(\.label), ["Downloads"])
        XCTAssertEqual(Guidance.score(request: "downloads", label: result[0].label) > 0, true)
    }
    func testEditableTextIsNeverTreatedAsItsLabel() {
        let nodes = [
            ControlNode(id: 0, parent: nil, role: "AXWindow"),
            ControlNode(id: 1, parent: 0, role: "AXTextField", frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        ]
        XCTAssertEqual(ControlIndex.candidates(in: nodes).count, 0)
    }
    func testLabelledButtonInAnotherAppShape() {
        let nodes = [
            ControlNode(id: 0, parent: nil, role: "AXWindow"),
            ControlNode(id: 1, parent: 0, role: "AXGroup"),
            ControlNode(id: 2, parent: 1, role: "AXButton", description: "Attach file", frame: CGRect(x: 100, y: 100, width: 90, height: 30)),
            ControlNode(id: 3, parent: 2, role: "AXStaticText", staticText: "Attach file"),
            ControlNode(id: 4, parent: 1, role: "AXButton", title: "Send", frame: CGRect(x: 200, y: 100, width: 60, height: 30), enabled: false)
        ]
        let result = ControlIndex.candidates(in: nodes)
        XCTAssertEqual(result.map(\.nodeID), [2])
        XCTAssertEqual(result.map(\.label), ["Attach file"])
    }
    func testSharedStemMatchesButShortFragmentsDoNot() {
        XCTAssertEqual(Guidance.score(request: "downloads", label: "Downloads"), 15)
        XCTAssertEqual(Guidance.score(request: "download", label: "Downloads"), 6)
        XCTAssertEqual(Guidance.score(request: "open downloads folder", label: "Downloads") > Guidance.score(request: "open downloads folder", label: "Download settings"), true)
        XCTAssertEqual(Guidance.score(request: "add", label: "Address book"), 0)
        XCTAssertEqual(Guidance.score(request: "dl", label: "Downloads"), 0)
    }
    func testDiagnosisPrefersMostFundamentalCause() {
        let found = ScanStats(window: .found, labelledControls: 40)
        XCTAssertEqual(Diagnostics.diagnose(trusted: false, stats: found, request: "downloads", matches: 3), .permissionMissing)
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: ScanStats(window: .permissionDenied), request: "x", matches: 0), .permissionMissing)
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: ScanStats(window: .appUnavailable), request: "downloads", matches: 0), .appUnavailable)
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: ScanStats(window: .noWindow), request: "downloads", matches: 0), .noWindow)
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: ScanStats(window: .notResponding), request: "downloads", matches: 0), .appNotResponding)
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: ScanStats(window: .found, unlabelledInteractive: 7), request: "downloads", matches: 0), .noExposedControls(unlabelled: 7))
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: found, request: "find the button", matches: 0), .unsearchableRequest)
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: found, request: "downloads", matches: 0), .noMatch(controls: 40))
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: found, request: "help me", matches: 0, usedModel: true), .modelChoseNone(controls: 40))
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: found, request: "downloads", matches: 2), .matches(2))
    }
    func testIncompleteScanIsExplainedOnlyWhenIncomplete() {
        let complete = ScanStats(window: .found, labelledControls: 40)
        var partial = complete; partial.limits = [.timeLimit, .elementLimit]; partial.failedReads = 2
        let quiet = Diagnostics.message(.noMatch(controls: 40), appName: "Finder", stats: complete)
        let noisy = Diagnostics.message(.noMatch(controls: 40), appName: "Finder", stats: partial)
        XCTAssertEqual(quiet.contains("not read"), false)
        XCTAssertEqual(noisy.contains("element limit, time limit, 2 failed reads"), true)
        XCTAssertEqual(partial.incomplete && !complete.incomplete, true)
    }
    func testDiagnosticsNeverContainScreenText() {
        let nodes = [
            ControlNode(id: 0, parent: nil, role: "AXWindow", title: "Private Budget 2026.xlsx"),
            ControlNode(id: 1, parent: 0, role: "AXOutline"),
            ControlNode(id: 2, parent: 1, role: "AXRow", frame: CGRect(x: 0, y: 0, width: 100, height: 20)),
            ControlNode(id: 3, parent: 2, role: "AXStaticText", staticText: "Medical letter.pdf"),
            ControlNode(id: 4, parent: 0, role: "AXButton", frame: CGRect(x: 0, y: 30, width: 20, height: 20)),
            ControlNode(id: 5, parent: 0, role: "AXTextField", frame: CGRect(x: 0, y: 60, width: 80, height: 20))
        ]
        let indexed = ControlIndex.candidates(in: nodes)
        let stats = ScanStats.from(nodes: nodes, indexed: indexed, limits: [.depthLimit], failedReads: 0, seconds: 0.4)
        XCTAssertEqual(stats.labelledControls, 1)
        XCTAssertEqual(stats.unlabelledInteractive, 2)
        let summary = Diagnostics.summary(stats, appName: "Finder")
        XCTAssertEqual(summary, "Finder: window found · 6 elements read · 1 named controls (Row 1) · 2 unnamed · 0.4 s · stopped: depth limit")
        for diagnosis in [Diagnosis.noMatch(controls: 1), .noExposedControls(unlabelled: 2), .matches(1)] {
            let text = Diagnostics.message(diagnosis, appName: "Finder", stats: stats) + summary
            XCTAssertEqual(text.contains("Budget") || text.contains("Medical"), false)
        }
    }
    func testTableRowsExposedOnlyThroughAXRows() {
        // No AXVisibleRows; AXChildren holds only a column. Rows must still be read via AXRows.
        let tree = FakeTree([
            app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: ["AXRole": .string("AXTable"), "frame": .frame(box), "AXChildren": .elements([9]), "AXRows": .elements([3, 4])],
            9: ["AXRole": .string("AXColumn")],
            3: row(5), 5: text("Downloads"), 4: row(6), 6: text("Documents")
        ])
        let (result, stats) = scan(tree)
        XCTAssertEqual(ControlIndex.candidates(in: result.nodes).map(\.label).sorted(), ["Documents", "Downloads"])
        XCTAssertEqual(result.nodes.contains { $0.role == "AXColumn" }, true)
        XCTAssertEqual(stats.incomplete, false)
    }
    func testSupportedVisibleRowsAreRespectedWithoutQueuingEveryRow() {
        var nodes: [Int: [String: FakeValue]] = [
            app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: ["AXRole": .string("AXTable"), "frame": .frame(box), "AXVisibleRows": .elements([3]), "AXHeader": .element(7),
                "AXRows": .elements([3] + Array(1000..<4000)), "AXChildren": .elements([3] + Array(1000..<4000))],
            3: row(5), 5: text("Downloads"),
            7: ["AXRole": .string("AXGroup"), "AXChildren": .elements([8])],
            8: ["AXRole": .string("AXButton"), "AXTitle": .string("Name"), "frame": .frame(box)]
        ]
        for id in 1000..<4000 { nodes[id] = row(5) }
        let tree = FakeTree(nodes)
        let (result, stats) = scan(tree)
        XCTAssertEqual(ControlIndex.candidates(in: result.nodes).map(\.label).sorted(), ["Downloads", "Name"])
        XCTAssertEqual(tree.reads.contains("2.AXRows"), false)
        XCTAssertEqual(tree.transferred < 100, true)
        XCTAssertEqual(stats.incomplete, false)
    }
    func testHugeRowListIsBoundedAndReportedAsIncomplete() {
        var nodes: [Int: [String: FakeValue]] = [
            app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: ["AXRole": .string("AXOutline"), "frame": .frame(box), "AXRows": .elements(Array(1000..<6000))]
        ]
        for id in 1000..<6000 { nodes[id] = ["AXRole": .string("AXRow"), "frame": .frame(box)] }
        let tree = FakeTree(nodes)
        let (result, stats) = scan(tree, maxElements: 50)
        XCTAssertEqual(tree.transferred <= 50, true)
        XCTAssertEqual(result.nodes.count <= 50, true)
        XCTAssertEqual(stats.limits.contains(.elementLimit), true)
    }
    func testFailedChildReadAfterSuccessfulRoleIsNotReportedAsNoControls() {
        let tree = FakeTree([
            app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: ["AXRole": .string("AXGroup"), "frame": .frame(box), "AXChildren": .fail(.timeout)]
        ])
        let (_, stats) = scan(tree)
        XCTAssertEqual(stats.failedReads, 1)
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: stats, request: "downloads", matches: 0), .controlsNotFullyRead)
        XCTAssertEqual(Diagnostics.message(.controlsNotFullyRead, appName: "Finder", stats: stats).contains("1 failed reads"), true)
    }
    func testCompleteEmptyScanReportsNoExposedControls() {
        let tree = FakeTree([
            app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: ["AXRole": .string("AXGroup"), "frame": .frame(box)]
        ])
        let (result, stats) = scan(tree)
        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertEqual(stats.incomplete, false)
        XCTAssertEqual(Diagnostics.diagnose(trusted: true, stats: stats, request: "downloads", matches: 0), .noExposedControls(unlabelled: 0))
    }
    func testWindowFallbackValidatesEveryCandidateAndKeepsErrors() {
        func lookup(_ nodes: [Int: [String: FakeValue]]) -> (Int?, WindowLookup) {
            var scanner = TreeScanner(reader: FakeTree(nodes), budget: 3)
            let result = scanner.lookupWindow(app: app)
            return (result.window, result.windowStatus)
        }
        let minimised = window(children: [], extra: ["AXMinimized": .bool(true)])
        // A minimised main window is skipped exactly like a minimised listed window.
        let fallback = lookup([app: ["AXMainWindow": .element(1), "AXWindows": .elements([1, 2, 3])],
                               1: minimised, 2: ["AXRole": .string("AXWindow"), "AXSubrole": .string("AXUnknown")], 3: window(children: [])])
        XCTAssertEqual(fallback.0, 3); XCTAssertEqual(fallback.1, .found)
        // A timeout on the main-window read is not collapsed into "no window".
        XCTAssertEqual(lookup([app: ["AXMainWindow": .fail(.timeout)]]).1, .notResponding)
        XCTAssertEqual(lookup([app: ["AXWindows": .fail(.other)]]).1, .notResponding)
        // A window whose minimised state cannot be read is rejected and the failure kept.
        XCTAssertEqual(lookup([app: ["AXFocusedWindow": .element(1)], 1: window(children: [], extra: ["AXMinimized": .fail(.timeout)])]).1, .notResponding)
        XCTAssertEqual(lookup([app: ["AXFocusedWindow": .fail(.permission)]]).1, .permissionDenied)
        XCTAssertEqual(lookup([app: ["AXMainWindow": .fail(.permission)]]).1, .permissionDenied)
        XCTAssertEqual(lookup([app: ["AXFocusedWindow": .fail(.invalidElement)]]).1, .appUnavailable)
        XCTAssertEqual(lookup([app: ["AXWindows": .elements([])]]).1, .noWindow)
        XCTAssertEqual(lookup([app: ["AXFocusedWindow": .element(1)], 1: window(children: [], extra: ["AXSheets": .elements([8])])]).0, 8)
    }
    func testDeadlineIsCheckedBeforeEveryRead() {
        var nodes: [Int: [String: FakeValue]] = [app: ["AXFocusedWindow": .element(1)], 1: window(children: Array(1000..<1500))]
        for id in 1000..<1500 { nodes[id] = ["AXRole": .string("AXButton"), "AXTitle": .string("B"), "frame": .frame(box)] }
        let tree = FakeTree(nodes)
        var now = Date(timeIntervalSince1970: 0)
        let (result, stats) = scan(tree, budget: 1, clock: { defer { now += 0.1 }; return now })
        // Each read costs 0.1 s on the fake clock, so at most 10 reads fit in a 1 s budget.
        XCTAssertEqual(tree.reads.count <= 10, true)
        XCTAssertEqual(stats.limits.contains(.timeLimit), true)
        XCTAssertEqual(result.windowStatus, .found)
    }
    func testPermissionLostDuringTraversal() {
        let tree = FakeTree([
            app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: ["AXRole": .string("AXGroup"), "AXTitle": .fail(.permission)]
        ])
        XCTAssertEqual(scan(tree).0.windowStatus, .permissionDenied)
    }

    func labels(_ tree: FakeTree) -> [String] { ControlIndex.candidates(in: scan(tree).0.nodes).map(\.label).sorted() }
    func table(_ attributes: [String: FakeValue]) -> [String: FakeValue] {
        ["AXRole": .string("AXTable"), "frame": .frame(box)].merging(attributes) { $1 }
    }
    func testSupportedEmptyVisibleRowsHideRowsFromChildren() {
        // Case A: AXVisibleRows = [] is authoritative; a row listed in AXChildren is hidden.
        XCTAssertEqual(labels(FakeTree([app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: table(["AXVisibleRows": .elements([]), "AXChildren": .elements([3])]), 3: row(4), 4: text("Hidden row")])), [])
    }
    func testOnlySupportedVisibleRowsAreIndexed() {
        // Case B: AXVisibleRows = [3]; AXChildren = [3, 5]. Row 5 must not be suggested.
        let tree = FakeTree([app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: table(["AXVisibleRows": .elements([3]), "AXChildren": .elements([3, 5])]),
            3: row(4), 4: text("Visible row"), 5: row(6), 6: text("Hidden row")])
        XCTAssertEqual(labels(tree), ["Visible row"])
        XCTAssertEqual(tree.reads.filter { $0 == "3.AXRole" }.count, 1)
    }
    func testNonRowTableChildrenSurviveWithEmptyVisibleRows() {
        // Header, column contents and other controls stay; a hidden row reached through a column is still hidden.
        let tree = FakeTree([app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: table(["AXVisibleRows": .elements([]), "AXHeader": .element(7), "AXChildren": .elements([3, 9, 10])]),
            3: row(4), 4: text("Hidden row"),
            7: ["AXRole": .string("AXGroup"), "AXChildren": .elements([8])],
            8: ["AXRole": .string("AXButton"), "AXTitle": .string("Name"), "frame": .frame(box)],
            9: ["AXRole": .string("AXColumn"), "AXChildren": .elements([11, 12])],
            11: ["AXRole": .string("AXButton"), "AXTitle": .string("Sort"), "frame": .frame(box)],
            12: row(13), 13: text("Hidden via column"),
            10: ["AXRole": .string("AXButton"), "AXTitle": .string("Add row"), "frame": .frame(box)]])
        let (result, stats) = scan(tree)
        XCTAssertEqual(ControlIndex.candidates(in: result.nodes).map(\.label).sorted(), ["Add row", "Name", "Sort"])
        XCTAssertEqual(stats.incomplete, false)
    }
    func testUnsupportedOrFailedVisibleRowsKeepAXRowsFallback() {
        // Unsupported visibility: rows come from AXRows and no row is treated as hidden.
        XCTAssertEqual(labels(FakeTree([app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: table(["AXRows": .elements([3]), "AXChildren": .elements([3, 5])]),
            3: row(4), 4: text("First"), 5: row(6), 6: text("Second")])), ["First", "Second"])
        // A failed visibility read also falls back, and the failure stays visible in the stats.
        let (result, stats) = scan(FakeTree([app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: table(["AXVisibleRows": .fail(.timeout), "AXRows": .elements([3])]), 3: row(4), 4: text("First")]))
        XCTAssertEqual(ControlIndex.candidates(in: result.nodes).map(\.label), ["First"])
        XCTAssertEqual(stats.failedReads, 1)
        // A nested table without visibility support resets the context set by its outer table.
        XCTAssertEqual(labels(FakeTree([app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: table(["AXVisibleRows": .elements([3])]), 3: row(20),
            20: table(["AXRows": .elements([21])]), 21: row(22), 22: text("Inner row")])), ["Inner row"])
    }
    func testScreenFallbackIsOfferedOnlyOnCompleteAccessibilityEvidence() {
        let complete = ScanStats(window: .found, labelledControls: 12, unlabelledInteractive: 3)
        var partial = complete; partial.failedReads = 2
        var named = complete; named.unlabelledInteractive = 0
        XCTAssertEqual(ScreenFallback.decide(.noExposedControls(unlabelled: 3), stats: ScanStats(window: .found, unlabelledInteractive: 3)), .offerScreenImage(unlabelled: 3))
        XCTAssertEqual(ScreenFallback.decide(.noExposedControls(unlabelled: 0), stats: partial), .retryAccessibility)
        XCTAssertEqual(ScreenFallback.decide(.controlsNotFullyRead, stats: partial), .retryAccessibility)
        XCTAssertEqual(ScreenFallback.decide(.noMatch(controls: 12), stats: complete), .offerScreenImage(unlabelled: 3))
        XCTAssertEqual(ScreenFallback.decide(.noMatch(controls: 12), stats: partial), .retryAccessibility)
        XCTAssertEqual(ScreenFallback.decide(.noMatch(controls: 12), stats: named), .rephrase)
        XCTAssertEqual(ScreenFallback.decide(.modelChoseNone(controls: 12), stats: complete), .offerScreenImage(unlabelled: 3))
        XCTAssertEqual(ScreenFallback.decide(.matches(2), stats: complete), .notNeeded)
        XCTAssertEqual(ScreenFallback.decide(.unsearchableRequest, stats: complete), .rephrase)
        XCTAssertEqual(ScreenFallback.decide(.appNotResponding, stats: ScanStats(window: .notResponding)), .retryAccessibility)
        for diagnosis in [Diagnosis.permissionMissing, .appUnavailable, .noWindow] {
            XCTAssertEqual(ScreenFallback.decide(diagnosis, stats: ScanStats(window: .noWindow)), .fixAccessFirst)
        }
        // End to end from the scanner: a genuinely empty window offers an image; a failed read does not.
        func decision(_ tree: FakeTree) -> FallbackDecision {
            let stats = scan(tree).1
            return ScreenFallback.decide(Diagnostics.diagnose(trusted: true, stats: stats, request: "downloads", matches: 0), stats: stats)
        }
        XCTAssertEqual(decision(FakeTree([app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: ["AXRole": .string("AXButton"), "frame": .frame(box)]])), .offerScreenImage(unlabelled: 1))
        XCTAssertEqual(decision(FakeTree([app: ["AXFocusedWindow": .element(1)], 1: window(children: [2]),
            2: ["AXRole": .string("AXGroup"), "frame": .frame(box), "AXChildren": .fail(.timeout)]])), .retryAccessibility)
    }
    func testCaptureGeometryMapsImagePixelsToScreenPoints() {
        let window = CGRect(x: -800, y: 100, width: 400, height: 300)
        let geometry = CaptureGeometry(windowFrame: window, imageSize: CGSize(width: 800, height: 600))!
        XCTAssertEqual(geometry.scale, 2)
        XCTAssertEqual(geometry.screenRect(imageRect: CGRect(x: 100, y: 50, width: 40, height: 20)), CGRect(x: -750, y: 125, width: 20, height: 10))
        XCTAssertEqual(geometry.screenRect(imageRect: CGRect(x: 780, y: 590, width: 40, height: 20)), nil)
        XCTAssertEqual(geometry.screenRect(imageRect: CGRect(x: 10, y: 10, width: 0, height: 20)), nil)
        XCTAssertEqual(geometry.screenRect(imageRect: CGRect(x: CGFloat.nan, y: 10, width: 4, height: 4)), nil)
        XCTAssertEqual(CaptureGeometry(windowFrame: window, imageSize: CGSize(width: 801, height: 600)) != nil, true)
        XCTAssertEqual(CaptureGeometry(windowFrame: window, imageSize: CGSize(width: 800, height: 500)), nil)
        XCTAssertEqual(CaptureGeometry(windowFrame: window, imageSize: CGSize(width: 4000, height: 3000)), nil)
        XCTAssertEqual(CaptureGeometry(windowFrame: .zero, imageSize: CGSize(width: 800, height: 600)), nil)
    }
    func testWindowMatcherRefusesToGuess() {
        let frame = CGRect(x: 100, y: 80, width: 600, height: 400)
        let shifted = CGRect(x: 102, y: 81, width: 599, height: 401)
        let windows = [
            CaptureWindow(id: 1, pid: 7, frame: frame, onScreen: false),
            CaptureWindow(id: 2, pid: 8, frame: frame),
            CaptureWindow(id: 3, pid: 7, frame: frame, layer: 3),
            CaptureWindow(id: 4, pid: 7, frame: shifted),
            CaptureWindow(id: 5, pid: 7, frame: frame.offsetBy(dx: 30, dy: 0))
        ]
        XCTAssertEqual(WindowMatcher.match(pid: 7, accessibilityFrame: frame, in: windows), .match(windows[3]))
        XCTAssertEqual(WindowMatcher.match(pid: 7, accessibilityFrame: frame, in: windows + [CaptureWindow(id: 6, pid: 7, frame: frame)]), .ambiguous(2))
        XCTAssertEqual(WindowMatcher.match(pid: 9, accessibilityFrame: frame, in: windows), .notFound)
        XCTAssertEqual(WindowMatcher.outputSize(points: CGSize(width: 1600, height: 1000), pixelScale: 2), CGSize(width: 2048, height: 1280))
        XCTAssertEqual(WindowMatcher.outputSize(points: CGSize(width: 400, height: 300), pixelScale: 2), CGSize(width: 800, height: 600))
    }
    func testVisualProposalsAreBoundedAndNeverVerified() {
        let geometry = CaptureGeometry(windowFrame: CGRect(x: 0, y: 0, width: 400, height: 300), imageSize: CGSize(width: 800, height: 600))!
        let candidates = [
            VisualCandidate(label: " Downloads ", imageRect: CGRect(x: 20, y: 40, width: 200, height: 40), confidence: 0.7),
            VisualCandidate(label: "Search", imageRect: CGRect(x: 600, y: 20, width: 120, height: 40), confidence: 0.9),
            VisualCandidate(label: "Low", imageRect: CGRect(x: 20, y: 100, width: 50, height: 20), confidence: 0.2),
            VisualCandidate(label: "Outside", imageRect: CGRect(x: 790, y: 20, width: 50, height: 20), confidence: 0.9),
            VisualCandidate(label: "Whole window", imageRect: CGRect(x: 0, y: 0, width: 800, height: 600), confidence: 0.9),
            VisualCandidate(label: "Tiny", imageRect: CGRect(x: 5, y: 5, width: 2, height: 2), confidence: 0.9),
            VisualCandidate(label: "Bad", imageRect: CGRect(x: 5, y: 5, width: 20, height: 20), confidence: 1.4),
            VisualCandidate(label: "  ", imageRect: CGRect(x: 5, y: 5, width: 20, height: 20), confidence: 0.9)
        ]
        let targets = VisualProposals.validate(candidates, geometry: geometry)
        XCTAssertEqual(targets.map(\.label), ["Search", "Downloads"])
        XCTAssertEqual(targets.map(\.screenRect), [CGRect(x: 300, y: 10, width: 60, height: 20), CGRect(x: 10, y: 20, width: 100, height: 20)])
        XCTAssertEqual(targets.allSatisfy { !$0.verified }, true)
        XCTAssertEqual(VisualProposals.validate(Array(repeating: candidates[1], count: 9), geometry: geometry).count, 5)
    }
    func testEvaluationRequiresLabelAndOverlap() {
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(VisualEvaluation.iou(a, a), 1)
        XCTAssertEqual(VisualEvaluation.iou(a, a.offsetBy(dx: 20, dy: 0)), 0)
        XCTAssertEqual(VisualEvaluation.iou(a, a.offsetBy(dx: 5, dy: 0)), 50.0 / 150.0)
        let truth = [LabeledBox(label: "Downloads", rect: a), LabeledBox(label: "Search", rect: a.offsetBy(dx: 100, dy: 0))]
        let result = VisualEvaluation.evaluate(predictions: [
            LabeledBox(label: "downloads", rect: a.offsetBy(dx: 1, dy: 0)),       // correct
            LabeledBox(label: "Close", rect: a.offsetBy(dx: 100, dy: 0)),         // right place, wrong label
            LabeledBox(label: "Search", rect: a.offsetBy(dx: 300, dy: 0)),        // right label, wrong place
            LabeledBox(label: "Downloads", rect: a)                               // duplicate of a matched truth
        ], truth: truth)
        XCTAssertEqual(result.truePositives, 1)
        XCTAssertEqual(result.precision, 0.25)
        XCTAssertEqual(result.recall, 0.5)
    }
    func testSyntheticScreenGroundTruthMatchesRenderedPixels() {
        let controls = [SyntheticScreen.Control(label: "Downloads", rect: CGRect(x: 20, y: 40, width: 140, height: 28)),
                        SyntheticScreen.Control(label: "Attach file", rect: CGRect(x: 240, y: 230, width: 120, height: 28))]
        let rendered = SyntheticScreen.render(size: CGSize(width: 400, height: 300), scale: 2, controls: controls)!
        XCTAssertEqual([rendered.image.width, rendered.image.height], [800, 600])
        XCTAssertEqual(rendered.truth.map(\.rect), [CGRect(x: 40, y: 80, width: 280, height: 56), CGRect(x: 480, y: 460, width: 240, height: 56)])
        // Read pixels back (top-left origin) and check each truth box is drawn where it says.
        var pixels = [UInt8](repeating: 0, count: 800 * 600 * 4)
        let context = CGContext(data: &pixels, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 800 * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(rendered.image, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        func isControl(_ x: Int, _ y: Int) -> Bool { let i = (y * 800 + x) * 4; return Int(pixels[i + 2]) > Int(pixels[i]) + 60 }
        for box in rendered.truth {
            XCTAssertEqual(isControl(Int(box.rect.maxX) - 4, Int(box.rect.minY) + 4), true)   // inside, clear of the text
            XCTAssertEqual(isControl(Int(box.rect.maxX) + 4, Int(box.rect.midY)), false)      // just outside
        }
    }
    func testSyntheticAnalyzerPathEndToEnd() async throws {
        struct Echo: VisualAnalyzer {   // stands in for a future model; returns truth plus one bad box
            let boxes: [LabeledBox]
            func candidates(in image: CGImage, request: String) async throws -> [VisualCandidate] {
                boxes.map { VisualCandidate(label: $0.label, imageRect: $0.rect.offsetBy(dx: 2, dy: 2), confidence: 0.8) }
                    + [VisualCandidate(label: "Ghost", imageRect: CGRect(x: 900, y: 0, width: 40, height: 40), confidence: 0.99)]
            }
        }
        let controls = [SyntheticScreen.Control(label: "Downloads", rect: CGRect(x: 20, y: 40, width: 140, height: 28))]
        let rendered = SyntheticScreen.render(size: CGSize(width: 400, height: 300), scale: 2, controls: controls)!
        let found = try await Echo(boxes: rendered.truth).candidates(in: rendered.image, request: "downloads")
        let geometry = CaptureGeometry(windowFrame: CGRect(x: 500, y: 200, width: 400, height: 300),
                                       imageSize: CGSize(width: rendered.image.width, height: rendered.image.height))!
        let targets = VisualProposals.validate(found, geometry: geometry)
        XCTAssertEqual(targets.map(\.label), ["Downloads"])
        XCTAssertEqual(targets[0].screenRect, CGRect(x: 521, y: 241, width: 140, height: 28))
        let score = VisualEvaluation.evaluate(predictions: found.map { LabeledBox(label: $0.label, rect: $0.imageRect) }, truth: rendered.truth)
        XCTAssertEqual([score.truePositives, score.predictions, score.truths], [1, 2, 1])
    }
    func testCaptureOfferIsBoundToItsScan() {
        let frame = CGRect(x: 100, y: 80, width: 600, height: 400)
        XCTAssertEqual(CaptureOffer(decision: .retryAccessibility, pid: 7, request: "downloads", windowFrame: frame), nil)
        XCTAssertEqual(CaptureOffer(decision: .offerScreenImage(unlabelled: 2), pid: 7, request: "downloads", windowFrame: nil), nil)
        let offer = CaptureOffer(decision: .offerScreenImage(unlabelled: 2), pid: 7, request: " downloads ", windowFrame: frame)!
        func now(pid: Int32 = 7, request: String = "downloads", same: Bool = true, frame current: CGRect? = frame) -> CaptureOffer.Observation {
            CaptureOffer.Observation(pid: pid, request: request, sameWindow: same, windowFrame: current)
        }
        XCTAssertEqual(offer.isCurrent(now()), true)
        XCTAssertEqual(offer.isCurrent(now(request: "downloads\n")), true)                  // whitespace only
        XCTAssertEqual(offer.isCurrent(now(pid: 8)), false)                                 // another app
        XCTAssertEqual(offer.isCurrent(now(request: "downloads folder")), false)            // request edited
        XCTAssertEqual(offer.isCurrent(now(same: false)), false)                            // another window, same frame
        XCTAssertEqual(offer.isCurrent(now(frame: frame.offsetBy(dx: 3, dy: 0))), false)    // window moved
        XCTAssertEqual(offer.isCurrent(now(frame: nil)), false)                             // frame unreadable
    }
    func testBoundedWaitReturnsAtDeadlineAndDropsLateResult() async throws {
        final class Late: @unchecked Sendable {
            private let lock = NSLock(); private var stored: [Int] = []
            func add(_ value: Int) { lock.withLock { stored.append(value) } }
            var values: [Int] { lock.withLock { stored } }
        }
        let late = Late()
        // Ignores cancellation, like a capture API without an abort: finishes after 1 s regardless.
        let stubborn: @Sendable () async throws -> Int = {
            await withCheckedContinuation { done in DispatchQueue.global().asyncAfter(deadline: .now() + 1) { done.resume(returning: 42) } }
        }
        let started = Date()
        var outcome: Error?
        do { _ = try await BoundedWait.run(seconds: 0.1, stubborn) { late.add($0) } }
        catch { outcome = error }
        let waited = Date().timeIntervalSince(started)
        XCTAssertEqual(outcome as? BoundedWaitError, .timedOut)
        XCTAssertEqual(waited < 0.5, true)
        XCTAssertEqual(late.values, [])                       // nothing late yet: the wait really ended early
        for _ in 0..<30 where late.values.isEmpty { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(late.values, [42])                     // the late result went to the discard path only
        // Normal completion and errors pass through unchanged.
        let quick = try await BoundedWait.run(seconds: 2) { 7 }
        XCTAssertEqual(quick, 7)
        do { _ = try await BoundedWait.run(seconds: 2) { () async throws -> Int in throw CocoaError(.userCancelled) }; XCTAssertEqual(true, false) }
        catch { XCTAssertEqual((error as? CocoaError)?.code, .userCancelled) }
    }
    func testVisionCoordinatesAreFlippedToTopLeftPixels() {
        // Vision: normalised, origin bottom-left. A box at the bottom-left corner ends at the image's last rows.
        XCTAssertEqual(VisionGeometry.pixelRect(normalized: CGRect(x: 0, y: 0, width: 0.25, height: 0.1), width: 800, height: 600),
                       CGRect(x: 0, y: 540, width: 200, height: 60))
        XCTAssertEqual(VisionGeometry.pixelRect(normalized: CGRect(x: 0.5, y: 0.9, width: 0.5, height: 0.1), width: 800, height: 600),
                       CGRect(x: 400, y: 0, width: 400, height: 60))
        XCTAssertEqual(VisionGeometry.pixelRect(normalized: CGRect(x: 0.9, y: 0.5, width: 0.3, height: 0.1), width: 800, height: 600), nil)
        XCTAssertEqual(VisionGeometry.pixelRect(normalized: CGRect(x: 0.1, y: 0.1, width: 0, height: 0.1), width: 800, height: 600), nil)
        XCTAssertEqual(VisionGeometry.pixelRect(normalized: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1), width: 0, height: 600), nil)
    }
    func testMergedLineIsSplitIntoSegmentsAndDuplicatesStayAmbiguous() {
        // One Vision line spanning three toolbar buttons: "Save   Don't Save   Save".
        let h: CGFloat = 20
        let line = RecognizedLine(text: "Save Don't Save Save", confidence: 1, words: [
            RecognizedWord(text: "Save", rect: CGRect(x: 10, y: 0, width: 40, height: h)),
            RecognizedWord(text: "Don't", rect: CGRect(x: 100, y: 0, width: 45, height: h)),
            RecognizedWord(text: "Save", rect: CGRect(x: 150, y: 0, width: 40, height: h)),   // 5 px gap: same label
            RecognizedWord(text: "Save", rect: CGRect(x: 260, y: 0, width: 40, height: h))])
        let found = TextMatcher.candidates(lines: [line], request: "save")
        XCTAssertEqual(found.map(\.label), ["Save", "Save"])            // "Don't Save" scores lower than exact "Save"
        XCTAssertEqual(found.map(\.imageRect.minX), [10, 260])
        XCTAssertEqual(TextMatcher.candidates(lines: [line], request: "don't save").map(\.label), ["Don't Save"])
        XCTAssertEqual(TextMatcher.candidates(lines: [line], request: "upload").count, 0)
        // Measured failure: Vision read "Don't Save" as "Dont savi". A partial match must not offer plain "Save".
        let misread = RecognizedLine(text: "Save Dont savi", confidence: 1, words: [
            RecognizedWord(text: "Save", rect: CGRect(x: 10, y: 0, width: 40, height: h)),
            RecognizedWord(text: "Dont", rect: CGRect(x: 100, y: 0, width: 45, height: h)),
            RecognizedWord(text: "savi", rect: CGRect(x: 150, y: 0, width: 40, height: h))])
        XCTAssertEqual(TextMatcher.candidates(lines: [misread], request: "don't save").count, 0)
    }
    func testRealOCROnBlankImageReturnsNothing() async throws {
        let blank = SyntheticScreen.render(size: CGSize(width: 300, height: 200), scale: 2, controls: [])!
        XCTAssertEqual(try await VisionTextAnalyzer().recognize(blank.image).count, 0)
        XCTAssertEqual(try await VisionTextAnalyzer(level: .fast).candidates(in: blank.image, request: "save").count, 0)
    }
    func testVisualMatchRequiresTheSameName() {
        // Extra or different words can reverse or change the action; they must never match.
        for (request, shown) in [("Save", "Don't Save"), ("Delete", "Don't Delete"), ("Save", "Save as PDF"),
                                 ("Delete", "Deleted"), ("Send", "Do not send"), ("folder", "New Folder"), ("Save as PDF", "Save")] {
            XCTAssertEqual(Guidance.sameName(request: request, label: shown), false)
            let line = RecognizedLine(text: shown, confidence: 1, words: shown.split(separator: " ").enumerated().map { i, word in
                RecognizedWord(text: String(word), rect: CGRect(x: 10 + CGFloat(i) * 50, y: 0, width: 45, height: 20)) })
            XCTAssertEqual(TextMatcher.candidates(lines: [line], request: request).count, 0)
        }
        // Same name, allowing plural and filler words in the request.
        XCTAssertEqual(Guidance.sameName(request: "Save", label: "Save"), true)
        XCTAssertEqual(Guidance.sameName(request: "help me find the download button", label: "Downloads"), true)
        XCTAssertEqual(Guidance.sameName(request: "don't save", label: "Don't Save"), true)
        XCTAssertEqual(Guidance.sameName(request: "save as pdf", label: "Save as PDF"), true)
        XCTAssertEqual(Guidance.sameName(request: "help center", label: "Help Center"), true)
        let exact = RecognizedLine(text: "Save", confidence: 1, words: [RecognizedWord(text: "Save", rect: CGRect(x: 10, y: 0, width: 45, height: 20))])
        XCTAssertEqual(TextMatcher.candidates(lines: [exact], request: "save").map(\.label), ["Save"])
        // Accessibility search keeps its broader ranking: "Don't Save" still scores for "save" there.
        XCTAssertEqual(Guidance.score(request: "save", label: "Don't Save") > 0, true)
    }
    func testDiagnosticsProtocolAcceptsOnlyTheTinyCommandSet() {
        func parse(_ text: String) -> Result<DiagnosticsRequest, DiagnosticsError> { DiagnosticsProtocol.parse(Data(text.utf8)) }
        XCTAssertEqual(try? parse(#"{"v":1,"cmd":"status"}"#).get(), DiagnosticsRequest(command: .status, selection: nil))
        XCTAssertEqual(try? parse(#"{"v":1,"cmd":"scan","selection":4}"#).get(), DiagnosticsRequest(command: .scan, selection: 4))
        XCTAssertEqual(try? parse(#"{"v":1,"cmd":"self_check"}"#).get(), DiagnosticsRequest(command: .selfCheck, selection: nil))
        func failure(_ text: String) -> DiagnosticsError? { if case .failure(let e) = parse(text) { return e }; return nil }
        XCTAssertEqual(failure(#"{"v":1,"cmd":"click"}"#), .unknownCommand)
        XCTAssertEqual(failure(#"{"v":1,"cmd":"eval","code":"x"}"#), .malformed)          // unknown fields are refused
        XCTAssertEqual(failure(#"{"v":2,"cmd":"status"}"#), .unsupportedVersion)
        XCTAssertEqual(failure(#"{"v":true,"cmd":"status"}"#), .malformed)
        XCTAssertEqual(failure(#"{"v":1,"cmd":"status","selection":1}"#), .malformed)    // selection only for scan
        XCTAssertEqual(failure(#"{"v":1,"cmd":"scan","selection":-1}"#), .malformed)
        XCTAssertEqual(failure(#"["status"]"#), .malformed)
        XCTAssertEqual(failure(String(repeating: " ", count: 1025)), .tooLarge)
    }
    func testDiagnosticsGateRequiresConsentAndLimitsLiveScans() {
        var gate = DiagnosticsGate()
        let scan = DiagnosticsRequest(command: .scan, selection: nil), status = DiagnosticsRequest(command: .status, selection: nil)
        let t0 = Date(timeIntervalSince1970: 1000)
        func admit(_ r: DiagnosticsRequest, _ t: Date, selected: Bool = true, guiding: Bool = false) -> Result<Admission, DiagnosticsError> {
            gate.admit(r, now: t, hasSelection: selected, selectionGeneration: 3, guiding: guiding)
        }
        XCTAssertEqual(failure(admit(status, t0)), .disabled)
        let first = gate.enable(now: t0)
        XCTAssertEqual(failure(admit(status, t0)), nil)
        XCTAssertEqual(failure(admit(scan, t0, selected: false)), .noSelection)
        XCTAssertEqual(failure(admit(DiagnosticsRequest(command: .scan, selection: 2), t0)), .staleSelection)
        XCTAssertEqual(failure(admit(scan, t0, guiding: true)), .guidanceActive)
        gate.setUserWork(active: true)
        XCTAssertEqual(failure(admit(scan, t0)), .userWorkActive)
        gate.setUserWork(active: false)
        guard case .success(let held) = admit(DiagnosticsRequest(command: .scan, selection: 3), t0) else { return XCTAssertEqual("admitted", "refused") }
        XCTAssertEqual(failure(admit(scan, t0 + 2)), .busy)                 // one live scan at a time
        gate.finishLiveWork(held)
        XCTAssertEqual(failure(admit(scan, t0 + 0.5)), .rateLimited)
        XCTAssertEqual(failure(admit(DiagnosticsRequest(command: .selfCheck, selection: nil), t0 + 1.5, selected: false)), nil)
        gate.disable()
        XCTAssertEqual(failure(admit(status, t0 + 3)), .disabled)
        XCTAssertEqual(gate.enable(now: t0 + 4) != first, true)             // a new session id
        XCTAssertEqual(gate.requests, 0)
    }
    func testDiagnosticReportsAreRedactedAndSeparateTheCauses() {
        let tree = FakeTree([app: ["AXFocusedWindow": .element(1)],
            1: window(children: [2, 4]).merging(["AXTitle": .string("Private Budget 2026.xlsx")]) { $1 },
            2: ["AXRole": .string("AXRow"), "frame": .frame(box), "AXChildren": .elements([3])],
            3: ["AXRole": .string("AXStaticText"), "AXValue": .string("Medical letter.pdf")],
            4: ["AXRole": .string("AXButton"), "AXTitle": .string("Send to accountant"), "frame": .frame(box)]])
        let stats = scan(tree).1
        let report = ScanReport(evidence: .liveSelectedApp, trigger: .userFind, selectionGeneration: 7, targetBundleId: "com.example.app",
                                trusted: true, stats: stats, request: "find my tax return", matches: 0)
        let json = String(decoding: DiagnosticsProtocol.encode(report), as: UTF8.self)
        for secret in ["Budget", "Medical", "accountant", "tax", "return"] { XCTAssertEqual(json.contains(secret), false) }
        for key in ["\"named_controls\":2", "\"diagnosis\":\"no_match\"", "\"evidence\":\"live_ax_selected_app\"", "\"request_present\":true", "\"matches\":0"] {
            XCTAssertEqual(json.contains(key), true)
        }
        // The causes Codex needs to tell apart without screenshots get different codes.
        func code(_ stats: ScanStats, trusted: Bool = true, request: String = "downloads", matches: Int? = 0) -> String {
            ScanReport(evidence: .liveSelectedApp, trigger: .diagnostics, selectionGeneration: 0, targetBundleId: nil,
                       trusted: trusted, stats: stats, request: request, matches: matches).diagnosis
        }
        let complete = ScanStats(window: .found, elementsRead: 40, labelledControls: 12)
        var partial = complete; partial.labelledControls = 0; partial.failedReads = 3
        XCTAssertEqual(code(complete, trusted: false), "permission_missing")
        XCTAssertEqual(code(ScanStats(window: .permissionDenied)), "permission_missing")
        XCTAssertEqual(code(ScanStats(window: .noWindow)), "no_window")
        XCTAssertEqual(code(partial), "controls_not_fully_read")
        XCTAssertEqual(code(complete), "no_match")
        XCTAssertEqual(code(complete, request: "", matches: nil), "no_request")
        XCTAssertEqual(code(ScanStats(window: .noWindow), request: "", matches: nil), "no_window")
    }
    func testGuidanceHealthRecordsLifecycleAndRefreshes() {
        var health = GuidanceHealth()
        health.stopped(.newSearch)
        XCTAssertEqual(health.lastStopReason, nil)                 // stopping while idle records nothing
        health.validating(); health.started()
        health.refreshed(.ok); health.refreshed(.ok); health.paused()
        XCTAssertEqual(health.state, .pausedOtherApp)
        health.refreshed(.ok)
        XCTAssertEqual(health.state, .guiding)
        health.refreshed(.windowChanged); health.stopped(.windowChanged)
        XCTAssertEqual([health.refreshSuccesses, health.refreshFailures, health.guidanceStarts], [3, 1, 1])
        XCTAssertEqual(health.lastRefresh, .windowChanged)
        XCTAssertEqual(health.lastStopReason, .windowChanged)
        XCTAssertEqual(health.state, .idle)
    }
    func testSyntheticDiagnosticFixturesPassInThisBinary() {
        let report = DiagnosticFixtures.run()
        XCTAssertEqual(report.passed, report.total)
        XCTAssertEqual(Set(report.cases.map(\.observed)), ["matches", "no_match", "controls_not_fully_read", "no_window", "permission_missing", "app_not_responding"])
        XCTAssertEqual(String(decoding: DiagnosticsProtocol.encode(report), as: UTF8.self).contains("\"evidence\":\"synthetic\""), true)
    }
    func testDiagnosticsSocketIsPrivateBoundedAndClosesInstantly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gcdiag-\(UUID().uuidString.prefix(8))").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/d/diag.sock"
        let probe = HandlerProbe()
        let server = DiagnosticsServer(path: path) { data in
            if String(decoding: data, as: UTF8.self).contains("slow") { probe.enter(); try? await Task.sleep(nanoseconds: 1_500_000_000); probe.exit() }
            switch DiagnosticsProtocol.parse(data) {
            case .success(let request): return Data("{\"ok\":true,\"cmd\":\"\(request.command.rawValue)\"}\n".utf8)
            case .failure(let error): return DiagnosticsProtocol.error(error, session: nil)
            }
        }
        try server.start()
        var info = stat()
        lstat(path, &info); XCTAssertEqual(info.st_mode & 0o777, 0o600)
        lstat(root + "/d", &info); XCTAssertEqual(info.st_mode & 0o777, 0o700)
        func send(_ text: String) -> String { String(decoding: (try? DiagnosticsClient.send(Data(text.utf8), path: path)) ?? Data(), as: UTF8.self) }
        XCTAssertEqual(send(#"{"v":1,"cmd":"status"}"#), "{\"ok\":true,\"cmd\":\"status\"}\n")
        XCTAssertEqual(send(#"{"v":1,"cmd":"open_url"}"#).contains("unknown_command"), true)
        XCTAssertEqual(send(String(repeating: "x", count: 4000)).contains("request_too_large"), true)
        // A second server must not hijack a live socket, and must not remove it when it is released.
        var refused: DiagnosticsServer? = DiagnosticsServer(path: path) { _ in Data() }
        var occupied: DiagnosticsSocketError?
        do { try refused?.start() } catch { occupied = error as? DiagnosticsSocketError }
        XCTAssertEqual(occupied, .occupied)
        refused?.stop(); refused = nil                                     // explicit stop and deinit
        do { try DiagnosticsServer(path: path) { _ in Data() }.start() } catch {}   // temporary released at once
        XCTAssertEqual(FileManager.default.fileExists(atPath: path), true)
        XCTAssertEqual(send(#"{"v":1,"cmd":"status"}"#), "{\"ok\":true,\"cmd\":\"status\"}\n")   // still answers a fresh client
        // Turning diagnostics off cuts a request whose handler is provably running; no reply is written.
        let pending = Task.detached { try? DiagnosticsClient.send(Data(#"{"v":1,"cmd":"status","slow":1}"#.utf8), path: path) }
        await waitUntil { probe.entered == 1 }
        XCTAssertEqual(probe.entered, 1)                                   // the request reached the handler
        let stoppedAt = Date()
        server.stop()
        let cut = await pending.value
        XCTAssertEqual(cut != nil, true)                                   // it was connected (not a failed connect)…
        XCTAssertEqual(cut?.isEmpty, true)                                 // …and was disconnected without a reply
        XCTAssertEqual(Date().timeIntervalSince(stoppedAt) < 0.5, true)
        XCTAssertEqual(probe.exited, 0)                                    // the handler was still running when cut
        await waitUntil { probe.exited == 1 }                              // its owner closes the descriptor when it ends
        XCTAssertEqual(FileManager.default.fileExists(atPath: path), false)
        XCTAssertEqual((try? DiagnosticsClient.send(Data(#"{"v":1,"cmd":"status"}"#.utf8), path: path)) == nil, true)
        // Refuses a directory other users can enter, and a non-socket file at the socket path.
        let loose = root + "/loose"
        try FileManager.default.createDirectory(atPath: loose, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        var insecure: DiagnosticsSocketError?
        do { try DiagnosticsServer(path: loose + "/diag.sock") { _ in Data() }.start() } catch { insecure = error as? DiagnosticsSocketError }
        XCTAssertEqual(insecure, .insecureDirectory)
        let plain = root + "/d/diag.sock"
        FileManager.default.createFile(atPath: plain, contents: Data("x".utf8))
        var notSocket: DiagnosticsSocketError?
        do { try DiagnosticsServer(path: plain) { _ in Data() }.start() } catch { notSocket = error as? DiagnosticsSocketError }
        XCTAssertEqual(notSocket, .notASocket)
    }
    func testOldScanCompletionNeverReleasesANewerReservation() async {
        let clock = TestClock(), coordinator = DiagnosticsCoordinator(clock: { clock.now })
        let scan = DiagnosticsRequest(command: .scan, selection: nil)
        func admit() -> Result<Admission, DiagnosticsError> { coordinator.admit(scan, hasSelection: true, selectionGeneration: 1, guiding: false) }
        _ = coordinator.enable()
        guard case .success(let a) = admit() else { return XCTAssertEqual("A admitted", "refused") }
        let workA = SuspendedWork()
        let replyA = Task { await coordinator.runLive(a, waitLimit: 10, work: workA.work) }
        await waitUntil { workA.started }
        coordinator.disable(); _ = coordinator.enable()                 // toggle off and on: a new session
        XCTAssertEqual(workA.cancelled, true)
        clock.advance(2)
        XCTAssertEqual(failure(admit()), .busy)                          // A's AX work has not ended yet
        workA.complete(sampleOutcome)
        XCTAssertEqual(failure(await replyA.value), .disabled)            // A's late result is not published
        guard case .success(let b) = admit() else { return XCTAssertEqual("B admitted", "refused") }
        let workB = SuspendedWork()
        let replyB = Task { await coordinator.runLive(b, waitLimit: 10, work: workB.work) }
        await waitUntil { workB.started }
        coordinator.abandon(a)                                           // a stale admission cannot release B
        clock.advance(2)
        XCTAssertEqual(failure(admit()), .busy)
        workB.complete(sampleOutcome)
        XCTAssertEqual(failure(await replyB.value), nil)
        XCTAssertEqual(coordinator.liveWorkPending, false)
    }
    func testTimedOutScanKeepsTheQueueReservedUntilItsWorkEnds() async {
        let clock = TestClock(), coordinator = DiagnosticsCoordinator(clock: { clock.now })
        let scan = DiagnosticsRequest(command: .scan, selection: nil)
        func admit() -> Result<Admission, DiagnosticsError> { coordinator.admit(scan, hasSelection: true, selectionGeneration: 1, guiding: false) }
        _ = coordinator.enable()
        guard case .success(let a) = admit() else { return XCTAssertEqual("admitted", "refused") }
        let work = SuspendedWork(), started = Date()
        XCTAssertEqual(failure(await coordinator.runLive(a, waitLimit: 0.2, work: work.work)), .timedOut)
        XCTAssertEqual(Date().timeIntervalSince(started) < 1, true)
        XCTAssertEqual(work.cancelled, true)                             // the work is told to stop…
        for _ in 0..<3 { clock.advance(2); XCTAssertEqual(failure(admit()), .busy) }   // …and repeated requests do not queue more AX work
        work.complete(nil)
        clock.advance(2)
        XCTAssertEqual(failure(admit()), nil)
    }
    func testUserWorkRefusesAndPreemptsDiagnosticsOnTheSharedQueue() async {
        let clock = TestClock(), coordinator = DiagnosticsCoordinator(clock: { clock.now })
        let scan = DiagnosticsRequest(command: .scan, selection: nil)
        func admit() -> Result<Admission, DiagnosticsError> { coordinator.admit(scan, hasSelection: true, selectionGeneration: 1, guiding: false) }
        _ = coordinator.enable()
        coordinator.setUserWork(active: true)                            // Find controls running
        XCTAssertEqual(failure(admit()), .userWorkActive)
        coordinator.setUserWork(active: false)
        // Diagnostics admitted first and queued behind earlier work; then the user starts work.
        final class Counter: @unchecked Sendable { let lock = NSLock(); var value = 0; func add() { lock.withLock { value += 1 } }; var count: Int { lock.withLock { value } } }
        let queue = DispatchQueue(label: "test.shared-ax-queue"), blocker = DispatchSemaphore(value: 0), performed = Counter(), userRan = Counter()
        queue.async { blocker.wait() }
        guard case .success(let a) = admit() else { return XCTAssertEqual("admitted", "refused") }
        let work: DiagnosticsCoordinator.LiveWork = { ticket, done in
            queue.async { guard !ticket.isCancelled else { done(nil); return }; performed.add(); done(sampleOutcome) }
        }
        let reply = Task { await coordinator.runLive(a, waitLimit: 5, work: work) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.setUserWork(active: true)                            // returns at once; it never waits for diagnostics
        queue.async { userRan.add() }                                    // the user's own scan
        blocker.signal()
        XCTAssertEqual(failure(await reply.value), .preempted)
        XCTAssertEqual(performed.count, 0)                               // obsolete diagnostic AX work was skipped
        await waitUntil { userRan.count == 1 }
        XCTAssertEqual(userRan.count, 1)
        coordinator.setUserWork(active: false)
        // Work that already finished its AX reads is still not published if the user started meanwhile.
        clock.advance(2)
        guard case .success(let b) = admit() else { return XCTAssertEqual("admitted", "refused") }
        let suspended = SuspendedWork()
        let replyB = Task { await coordinator.runLive(b, waitLimit: 5, work: suspended.work) }
        await waitUntil { suspended.started }
        coordinator.setUserWork(active: true)
        suspended.complete(sampleOutcome)
        XCTAssertEqual(failure(await replyB.value), .preempted)
    }
    func testSelectionChangeDropsScanResultsButNotSelfChecks() async {
        let clock = TestClock(), coordinator = DiagnosticsCoordinator(clock: { clock.now })
        _ = coordinator.enable()
        guard case .success(let a) = coordinator.admit(DiagnosticsRequest(command: .scan, selection: nil), hasSelection: true, selectionGeneration: 1, guiding: false)
        else { return XCTAssertEqual("admitted", "refused") }
        let work = SuspendedWork()
        let reply = Task { await coordinator.runLive(a, waitLimit: 5, work: work.work) }
        await waitUntil { work.started }
        coordinator.selectionChanged()
        XCTAssertEqual(work.cancelled, true)
        work.complete(sampleOutcome)
        XCTAssertEqual(failure(await reply.value), .staleSelection)
        clock.advance(2)
        guard case .success(let own) = coordinator.admit(DiagnosticsRequest(command: .selfCheck, selection: nil), hasSelection: false, selectionGeneration: 2, guiding: false)
        else { return XCTAssertEqual("admitted", "refused") }
        let selfWork = SuspendedWork()
        let selfReply = Task { await coordinator.runLive(own, waitLimit: 5, work: selfWork.work) }
        await waitUntil { selfWork.started }
        coordinator.selectionChanged()                                   // irrelevant to GuideCursor's own window
        XCTAssertEqual(selfWork.cancelled, false)
        selfWork.complete(sampleOutcome)
        XCTAssertEqual(failure(await selfReply.value), nil)
        XCTAssertEqual(failure(coordinator.admit(DiagnosticsRequest(command: .selfCheck, selection: nil), hasSelection: false, selectionGeneration: 2, guiding: false)), .rateLimited)
    }
    func testScannerStopsBetweenReadsWhenCancelled() {
        var nodes: [Int: [String: FakeValue]] = [app: ["AXFocusedWindow": .element(1)], 1: window(children: Array(1000..<1400))]
        for id in 1000..<1400 { nodes[id] = ["AXRole": .string("AXButton"), "AXTitle": .string("B"), "frame": .frame(box)] }
        let tree = FakeTree(nodes)
        var scanner = TreeScanner(reader: tree, budget: 30, isCancelled: { tree.reads.count >= 40 })
        let result = scanner.scan(app: app)
        XCTAssertEqual(result.cancelled, true)
        XCTAssertEqual(tree.reads.count, 40)                              // no read after cancellation was seen
        XCTAssertEqual(result.limits.isEmpty, true)                       // cancellation is not reported as an app limit
    }
    func testReleasedServerClosesEveryAcceptedDescriptor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gcfd-\(UUID().uuidString.prefix(8))").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/d/diag.sock"
        final class Probe: @unchecked Sendable {
            let lock = NSLock(); var entered = 0, exited = 0
            func enter() { lock.withLock { entered += 1 } }; func exit() { lock.withLock { exited += 1 } }
            var counts: (Int, Int) { lock.withLock { (entered, exited) } }
        }
        let probe = Probe()
        let slowHandler: DiagnosticsServer.Handler = { _ in probe.enter(); try? await Task.sleep(nanoseconds: 400_000_000); probe.exit(); return Data("{}\n".utf8) }
        func cycle(_ n: Int) async throws {
            // Released while the handler is suspended.
            var server: DiagnosticsServer? = DiagnosticsServer(path: path, handler: slowHandler)
            try server?.start()
            let reply = Task.detached { try? DiagnosticsClient.send(Data(#"{"v":1,"cmd":"status"}"#.utf8), path: path) }
            await waitUntil { probe.counts.0 == n }
            server?.stop(); server = nil
            XCTAssertEqual((await reply.value).map(\.isEmpty) ?? true, true)   // disconnected, no late reply
            await waitUntil { probe.counts.1 == n }
            // Released while the request is still being read (partial line, no newline).
            var reading: DiagnosticsServer? = DiagnosticsServer(path: path, handler: slowHandler)
            try reading?.start()
            let raw = connectRaw(path)
            _ = "{\"v\":1".withCString { write(raw, $0, 6) }
            try await Task.sleep(nanoseconds: 150_000_000)
            reading?.stop(); reading = nil
            try await Task.sleep(nanoseconds: 150_000_000)
            close(raw)
        }
        try await cycle(1)                                                 // warm-up: runtime-created descriptors
        try await Task.sleep(nanoseconds: 200_000_000)
        let baseline = openDescriptors()
        for n in 2...5 { try await cycle(n) }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(openDescriptors(), baseline)
        // The path is reusable afterwards.
        let fresh = DiagnosticsServer(path: path) { _ in Data("{\"ok\":true}\n".utf8) }
        try fresh.start()
        XCTAssertEqual(String(decoding: try DiagnosticsClient.send(Data(#"{"v":1,"cmd":"status"}"#.utf8), path: path), as: UTF8.self), "{\"ok\":true}\n")
        fresh.stop()
    }
    func testStoppedOrRefusedServerNeverRemovesAnotherListener() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gcown-\(UUID().uuidString.prefix(8))").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/d/diag.sock"
        func answer(_ name: String) -> DiagnosticsServer.Handler { { _ in Data("{\"by\":\"\(name)\"}\n".utf8) } }
        func ask() -> String { String(decoding: (try? DiagnosticsClient.send(Data(#"{"v":1,"cmd":"status"}"#.utf8), path: path)) ?? Data(), as: UTF8.self) }
        var a: DiagnosticsServer? = DiagnosticsServer(path: path, handler: answer("a"))
        try a?.start()
        XCTAssertEqual(ask(), "{\"by\":\"a\"}\n")
        a?.stop()
        let b = DiagnosticsServer(path: path, handler: answer("b"))
        try b.start()
        a?.stop()                                                          // stopping the old instance again…
        a = nil                                                            // …and releasing it
        var never: DiagnosticsServer? = DiagnosticsServer(path: path, handler: answer("c"))   // never started
        never?.stop(); never = nil
        XCTAssertEqual(ask(), "{\"by\":\"b\"}\n")                     // the replacement is untouched
        b.stop(); b.stop()                                                 // idempotent
        XCTAssertEqual(FileManager.default.fileExists(atPath: path), false)
    }
}

let tests = GuidanceTests()
tests.testInsideTargetWaitsForUser()
tests.testTopLeftCoordinates()
tests.testDisplayConversionIncludingNegativeOrigin()
tests.testRegionInMovedWindow()
tests.testNoMatchAndNaturalRequest()
tests.testModelCannotInventControlIDs()
tests.testUnlabelledOutlineRowUsesVisibleChildText()
tests.testEditableTextIsNeverTreatedAsItsLabel()
tests.testLabelledButtonInAnotherAppShape()
tests.testSharedStemMatchesButShortFragmentsDoNot()
tests.testDiagnosisPrefersMostFundamentalCause()
tests.testIncompleteScanIsExplainedOnlyWhenIncomplete()
tests.testDiagnosticsNeverContainScreenText()
tests.testTableRowsExposedOnlyThroughAXRows()
tests.testSupportedVisibleRowsAreRespectedWithoutQueuingEveryRow()
tests.testHugeRowListIsBoundedAndReportedAsIncomplete()
tests.testFailedChildReadAfterSuccessfulRoleIsNotReportedAsNoControls()
tests.testCompleteEmptyScanReportsNoExposedControls()
tests.testWindowFallbackValidatesEveryCandidateAndKeepsErrors()
tests.testDeadlineIsCheckedBeforeEveryRead()
tests.testPermissionLostDuringTraversal()
tests.testSupportedEmptyVisibleRowsHideRowsFromChildren()
tests.testOnlySupportedVisibleRowsAreIndexed()
tests.testNonRowTableChildrenSurviveWithEmptyVisibleRows()
tests.testUnsupportedOrFailedVisibleRowsKeepAXRowsFallback()
tests.testScreenFallbackIsOfferedOnlyOnCompleteAccessibilityEvidence()
tests.testCaptureGeometryMapsImagePixelsToScreenPoints()
tests.testWindowMatcherRefusesToGuess()
tests.testVisualProposalsAreBoundedAndNeverVerified()
tests.testEvaluationRequiresLabelAndOverlap()
tests.testSyntheticScreenGroundTruthMatchesRenderedPixels()
// Keep top-level code synchronous; run the one async check to completion before continuing.
let asyncDone = DispatchSemaphore(value: 0)
Task.detached {
    try! await tests.testSyntheticAnalyzerPathEndToEnd()
    try! await tests.testBoundedWaitReturnsAtDeadlineAndDropsLateResult()
    try! await tests.testRealOCROnBlankImageReturnsNothing()
    try! await tests.testDiagnosticsSocketIsPrivateBoundedAndClosesInstantly()
    try! await tests.testReleasedServerClosesEveryAcceptedDescriptor()
    try! await tests.testStoppedOrRefusedServerNeverRemovesAnotherListener()
    await tests.testOldScanCompletionNeverReleasesANewerReservation()
    await tests.testTimedOutScanKeepsTheQueueReservedUntilItsWorkEnds()
    await tests.testUserWorkRefusesAndPreemptsDiagnosticsOnTheSharedQueue()
    await tests.testSelectionChangeDropsScanResultsButNotSelfChecks()
    asyncDone.signal()
}
asyncDone.wait()
tests.testCaptureOfferIsBoundToItsScan()
tests.testVisionCoordinatesAreFlippedToTopLeftPixels()
tests.testMergedLineIsSplitIntoSegmentsAndDuplicatesStayAmbiguous()
tests.testVisualMatchRequiresTheSameName()
tests.testDiagnosticsProtocolAcceptsOnlyTheTinyCommandSet()
tests.testDiagnosticsGateRequiresConsentAndLimitsLiveScans()
tests.testDiagnosticReportsAreRedactedAndSeparateTheCauses()
tests.testGuidanceHealthRecordsLifecycleAndRefreshes()
tests.testSyntheticDiagnosticFixturesPassInThisBinary()
tests.testScannerStopsBetweenReadsWhenCancelled()
print("PASS: 51 core checks (\(assertions) assertions)")
