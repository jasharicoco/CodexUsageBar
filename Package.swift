// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexUsageBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexUsageBar", targets: ["CodexUsageBar"]),
        .executable(name: "UpdateInstaller", targets: ["UpdateInstaller"]),
        .executable(name: "ParserChecks", targets: ["ParserChecks"])
    ],
    targets: [
        .executableTarget(name: "UpdateChecks", dependencies: ["CodexUsageCore"], path: "Tests/AppUpdateTests"),
        .executableTarget(name: "UpdateInstaller", dependencies: ["CodexUsageCore"]),
        .target(
            name: "CodexUsageCore",
            path: "Sources/CodexUsageCore"
        ),
        .executableTarget(
            name: "CodexUsageBar",
            dependencies: ["CodexUsageCore"],
            path: "Sources/CodexUsageBar"
        ),
        .executableTarget(
            name: "ParserChecks",
            dependencies: ["CodexUsageCore"],
            path: "Tests/CodexUsageBarTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
