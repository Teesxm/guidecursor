import CoreGraphics
import Foundation
import GuideCursorCore

// Opt-in integration checks that run Apple's Vision OCR on generated screens. Recognition can differ
// between macOS versions, so these are not part of the required core checks or CI.
// Run: swift run --package-path macos GuideCursorOCRChecks
var assertions = 0
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    assertions += 1
    guard actual == expected else { fatalError("Expected \(expected), got \(actual)", file: file, line: line) }
}

final class OCRChecks {
    func testRealOCRLocatesLabelsOnRetinaScreen() async throws {
        let controls = [SyntheticScreen.Control(label: "Downloads", rect: CGRect(x: 20, y: 40, width: 140, height: 28)),
                        SyntheticScreen.Control(label: "Attach file", rect: CGRect(x: 200, y: 40, width: 120, height: 28)),
                        SyntheticScreen.Control(label: "Recent documents", rect: CGRect(x: 20, y: 200, width: 200, height: 22), fontSize: 13, style: .plain)]
        let screen = SyntheticScreen.render(size: CGSize(width: 400, height: 300), scale: 2, controls: controls)!
        let analyzer = VisionTextAnalyzer(level: .accurate)
        // The two buttons share a baseline; each request must land inside its own control.
        for (request, index) in [("downloads", 0), ("attach file", 1), ("recent documents", 2)] {
            let found = try await analyzer.candidates(in: screen.image, request: request)
            XCTAssertEqual(found.count, 1)
            let box = screen.truth[index].rect
            XCTAssertEqual(box.contains(CGPoint(x: found[0].imageRect.midX, y: found[0].imageRect.midY)), true)
            XCTAssertEqual(VisualEvaluation.iou(found[0].imageRect, screen.text[index].rect) > 0.5, true)
            // Retina image pixels → screen points for a window at (500, 120): inside the control in points.
            let geometry = CaptureGeometry(windowFrame: CGRect(x: 500, y: 120, width: 400, height: 300), imageSize: CGSize(width: 800, height: 600))!
            let target = VisualProposals.validate(found, geometry: geometry)
            XCTAssertEqual(target.count, 1)
            XCTAssertEqual(controls[index].rect.offsetBy(dx: 500, dy: 120).contains(CGPoint(x: target[0].screenRect.midX, y: target[0].screenRect.midY)), true)
        }
        XCTAssertEqual(try await analyzer.candidates(in: screen.image, request: "upload").count, 0)
    }
    func testRealOCRKeepsDuplicateLabelsAmbiguous() async throws {
        let controls = [SyntheticScreen.Control(label: "Save", rect: CGRect(x: 20, y: 30, width: 80, height: 28)),
                        SyntheticScreen.Control(label: "Don't Save", rect: CGRect(x: 140, y: 30, width: 110, height: 28)),
                        SyntheticScreen.Control(label: "Save", rect: CGRect(x: 20, y: 220, width: 80, height: 28))]
        let screen = SyntheticScreen.render(size: CGSize(width: 400, height: 300), scale: 2, controls: controls)!
        let found = try await VisionTextAnalyzer().candidates(in: screen.image, request: "save")
        let score = VisualEvaluation.centreHits(predictions: found.map { LabeledBox(label: $0.label, rect: $0.imageRect) },
                                                controls: [screen.truth[0], screen.truth[2]])
        XCTAssertEqual([score.truePositives, score.predictions], [2, 2])   // both Saves, nothing inside "Don't Save"
    }
    func testRealOCRWithOnlyOppositeActionsSuggestsNothing() async throws {
        // The requested action is absent; only labels that contain its word are visible.
        let controls = [SyntheticScreen.Control(label: "Don't Save", rect: CGRect(x: 20, y: 30, width: 120, height: 28)),
                        SyntheticScreen.Control(label: "Don't Delete", rect: CGRect(x: 170, y: 30, width: 130, height: 28)),
                        SyntheticScreen.Control(label: "Save as PDF", rect: CGRect(x: 20, y: 120, width: 140, height: 22), fontSize: 13, style: .plain)]
        let screen = SyntheticScreen.render(size: CGSize(width: 400, height: 200), scale: 2, controls: controls)!
        let lines = try await VisionTextAnalyzer().recognize(screen.image)
        XCTAssertEqual(lines.isEmpty, false)                                               // text was seen…
        XCTAssertEqual(TextMatcher.candidates(lines: lines, request: "save").count, 0)     // …but nothing is suggested
        XCTAssertEqual(TextMatcher.candidates(lines: lines, request: "delete").count, 0)
    }
}

let checks = OCRChecks()
let done = DispatchSemaphore(value: 0)
Task.detached {
    try! await checks.testRealOCRLocatesLabelsOnRetinaScreen()
    try! await checks.testRealOCRKeepsDuplicateLabelsAmbiguous()
    try! await checks.testRealOCRWithOnlyOppositeActionsSuggestsNothing()
    done.signal()
}
done.wait()
print("PASS: 3 Vision OCR integration checks (\(assertions) assertions) on \(ProcessInfo.processInfo.operatingSystemVersionString)")
