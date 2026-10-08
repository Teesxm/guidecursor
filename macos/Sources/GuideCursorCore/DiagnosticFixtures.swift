import CoreGraphics
import Foundation

/// Deterministic in-memory accessibility trees, run through the same scanner and diagnosis code as
/// live scans. Results are `synthetic` evidence: they show this binary's logic, not any real app.
public enum DiagnosticFixtures {
    enum Value { case string(String), bool(Bool), element(Int), elements([Int]), frame(CGRect), fail(ReadFailure) }

    struct Tree: TreeReader {
        let attributes: [Int: [String: Value]]
        func key(_ element: Int) -> Int { element }
        private func get(_ e: Int, _ a: String) -> Value? { attributes[e]?[a] }
        func string(_ e: Int, _ a: String) -> Read<String> {
            switch get(e, a) { case .string(let v)?: return .value(v); case .fail(let f)?: return .failed(f); default: return .absent }
        }
        func bool(_ e: Int, _ a: String) -> Read<Bool> {
            switch get(e, a) { case .bool(let v)?: return .value(v); case .fail(let f)?: return .failed(f); default: return .absent }
        }
        func element(_ e: Int, _ a: String) -> Read<Int> {
            switch get(e, a) { case .element(let v)?: return .value(v); case .fail(let f)?: return .failed(f); default: return .absent }
        }
        func elements(_ e: Int, _ a: String, max: Int) -> Read<Slice<Int>> {
            switch get(e, a) {
            case .elements(let v)?: return .value(Slice(items: Array(v.prefix(max)), total: v.count))
            case .fail(let f)?: return .failed(f)
            default: return .absent
            }
        }
        func frame(_ e: Int) -> Read<CGRect> {
            switch get(e, "frame") { case .frame(let v)?: return .value(v); case .fail(let f)?: return .failed(f); default: return .absent }
        }
    }

    public struct Case: Codable, Equatable, Sendable {
        public let name: String
        public let expected: String
        public let observed: String
        public let pass: Bool
    }
    public struct Report: Encodable, Equatable, Sendable {
        public let evidence = "synthetic"
        public let passed: Int
        public let total: Int
        public let cases: [Case]
    }

    static let app = 100
    static let box = CGRect(x: 10, y: 10, width: 100, height: 20)
    static func window(_ children: [Int]) -> [String: Value] {
        ["AXRole": .string("AXWindow"), "AXSubrole": .string("AXStandardWindow"),
         "frame": .frame(CGRect(x: 0, y: 0, width: 800, height: 600)), "AXChildren": .elements(children)]
    }

    /// (name, tree, request, expected diagnosis code)
    static var cases: [(String, [Int: [String: Value]], String, String)] {
        let sidebar: [Int: [String: Value]] = [app: ["AXFocusedWindow": .element(1)], 1: window([2]),
            2: ["AXRole": .string("AXOutline"), "frame": .frame(box), "AXRows": .elements([3])],
            3: ["AXRole": .string("AXRow"), "frame": .frame(box), "AXChildren": .elements([4])],
            4: ["AXRole": .string("AXCell"), "frame": .frame(box), "AXChildren": .elements([5])],
            5: ["AXRole": .string("AXStaticText"), "AXValue": .string("Downloads")]]
        return [
            ("nested_row_label", sidebar, "downloads", "matches"),
            ("no_match_complete_scan", sidebar, "zzzz", "no_match"),
            ("failed_child_read", [app: ["AXFocusedWindow": .element(1)], 1: window([2]),
                                   2: ["AXRole": .string("AXGroup"), "frame": .frame(box), "AXChildren": .fail(.timeout)]],
             "downloads", "controls_not_fully_read"),
            ("no_window", [app: ["AXWindows": .elements([])]], "downloads", "no_window"),
            ("minimised_only", [app: ["AXMainWindow": .element(1)], 1: window([]).merging(["AXMinimized": .bool(true)]) { $1 }],
             "downloads", "no_window"),
            ("permission_denied", [app: ["AXFocusedWindow": .fail(.permission)]], "downloads", "permission_missing"),
            ("app_not_responding", [app: ["AXFocusedWindow": .fail(.timeout)]], "downloads", "app_not_responding")
        ]
    }

    public static func run() -> Report {
        let results = cases.map { name, attributes, request, expected -> Case in
            var scanner = TreeScanner(reader: Tree(attributes: attributes), budget: 3)
            let tree = scanner.scan(app: app)
            let stats = tree.windowStatus == .found
                ? ScanStats.from(nodes: tree.nodes, indexed: ControlIndex.candidates(in: tree.nodes), limits: tree.limits,
                                 failedReads: tree.failedReads, seconds: 0)
                : ScanStats(window: tree.windowStatus, failedReads: tree.failedReads, limits: tree.limits)
            let matches = ControlIndex.candidates(in: tree.nodes).filter { Guidance.score(request: request, label: $0.label) > 0 }.count
            let observed = DiagnosticsCodes.diagnosis(Diagnostics.diagnose(trusted: true, stats: stats, request: request, matches: matches))
            return Case(name: name, expected: expected, observed: observed, pass: observed == expected)
        }
        return Report(passed: results.filter(\.pass).count, total: results.count, cases: results)
    }
}
