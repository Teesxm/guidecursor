import CoreGraphics
import Foundation
import GuideCursorCore
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    guard actual == expected else { fatalError("Expected \(expected), got \(actual)", file: file, line: line) }
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
}

let tests = GuidanceTests()
tests.testInsideTargetWaitsForUser()
tests.testTopLeftCoordinates()
tests.testDisplayConversionIncludingNegativeOrigin()
tests.testRegionInMovedWindow()
tests.testNoMatchAndNaturalRequest()
tests.testModelCannotInventControlIDs()
print("PASS: 6 core checks (12 assertions)")
