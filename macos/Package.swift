// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "GuideCursor", platforms: [.macOS(.v13)], products: [.executable(name: "GuideCursor", targets: ["GuideCursor"])], targets: [
    .target(name: "GuideCursorCore"),
    .executableTarget(name: "GuideCursor", dependencies: ["GuideCursorCore"]),
    .executableTarget(name: "GuideCursorCoreChecks", dependencies: ["GuideCursorCore"], path: "Tests/GuideCursorCoreTests"),
    // Opt-in: real Vision OCR assertions, which can vary by macOS version. Not run in CI.
    .executableTarget(name: "GuideCursorOCRChecks", dependencies: ["GuideCursorCore"], path: "Tests/GuideCursorOCRChecks"),
    // Development client for the app's opt-in diagnostics connection; not part of the app bundle.
    .executableTarget(name: "GuideCursorDiag", dependencies: ["GuideCursorCore"]),
    // Offline OCR benchmark on generated screens; not part of the app bundle.
    .executableTarget(name: "GuideCursorVisionBench", dependencies: ["GuideCursorCore"])
])
