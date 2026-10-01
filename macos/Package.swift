// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "GuideCursor", platforms: [.macOS(.v13)], products: [.executable(name: "GuideCursor", targets: ["GuideCursor"])], targets: [
    .target(name: "GuideCursorCore"),
    .executableTarget(name: "GuideCursor", dependencies: ["GuideCursorCore"]),
    .executableTarget(name: "GuideCursorCoreChecks", dependencies: ["GuideCursorCore"], path: "Tests/GuideCursorCoreTests")
])
