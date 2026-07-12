// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sutto-mac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Sutto", targets: ["SuttoApp"])
    ],
    targets: [
        // Platform-independent domain logic. Must not import AppKit or any
        // other macOS UI framework so it stays heavily unit-testable.
        .target(name: "SuttoCore"),

        // AppKit shell: menu bar residency, windows, and OS integrations.
        .executableTarget(
            name: "SuttoApp",
            dependencies: ["SuttoCore"]
        ),

        .testTarget(
            name: "SuttoCoreTests",
            dependencies: ["SuttoCore"]
        ),
    ]
)
