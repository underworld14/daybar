// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DayBar",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "DayBarCore",
            path: "Sources/DayBarCore"
        ),
        .executableTarget(
            name: "DayBar",
            dependencies: ["DayBarCore"],
            path: "Sources/DayBar"
        ),
        // Headless verification runner (Command Line Tools has no XCTest/Testing module).
        // Run with: swift run DayBarChecks
        .executableTarget(
            name: "DayBarChecks",
            dependencies: ["DayBarCore"],
            path: "Sources/DayBarChecks"
        ),
    ],
    swiftLanguageModes: [.v5]
)
