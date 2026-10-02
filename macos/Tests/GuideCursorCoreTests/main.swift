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
print("PASS: 25 core checks (\(assertions) assertions)")
