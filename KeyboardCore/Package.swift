// swift-tools-version: 6.2
// Pure core: no UIKit, no SwiftUI, no app-extension APIs. `swift test --package-path KeyboardCore`
// runs on the macOS host with no simulator.
import PackageDescription

let package = Package(
    name: "KeyboardCore",
    // Floors chosen low on purpose: the core uses only Foundation, so any recent Mac can run
    // the tests. The app's own deployment target (iOS 27.0) is set in project.yml.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"]),
    ],
    targets: [
        // Default (nonisolated) actor isolation: every public type is a Sendable value type,
        // usable from the main-actor shell and from tests without hops.
        .target(name: "KeyboardCore"),
        // Swift Testing. Tests use only the public API (no @testable import), so they exercise
        // exactly what the shell can reach.
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
    ],
    swiftLanguageModes: [.v6]
)
