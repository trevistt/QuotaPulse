// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaPulse",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "QuotaPulseCore",
            targets: ["QuotaPulseCore"]),
        .executable(
            name: "QuotaPulse",
            targets: ["QuotaPulse"]),
    ],
    targets: [
        .target(
            name: "QuotaPulseCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .executableTarget(
            name: "QuotaPulse",
            dependencies: ["QuotaPulseCore"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .executableTarget(
            name: "QuotaPulseTestHarness",
            dependencies: ["QuotaPulseCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .testTarget(
            name: "QuotaPulseCoreTests",
            dependencies: ["QuotaPulseCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
                .linkedFramework("Testing"),
            ]),
    ])
