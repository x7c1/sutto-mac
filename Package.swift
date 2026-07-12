// swift-tools-version: 6.0
import PackageDescription

// Layered architecture with dependencies pointing inward toward the domain.
// See docs/guides/architecture.md for the full picture. The dependency lists
// below are the enforcement mechanism: an import that violates the layering
// fails to compile.
let package = Package(
    name: "sutto-mac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Sutto", targets: ["SuttoApp"])
    ],
    targets: [
        // Pure domain models and logic. Foundation only; must not import
        // AppKit, ApplicationServices, or any other macOS framework.
        .target(name: "SuttoDomain"),

        // Use cases coordinating the domain, plus the protocols that the
        // infra layer implements.
        .target(
            name: "SuttoOperations",
            dependencies: ["SuttoDomain"]
        ),

        // Concrete adapters over Apple frameworks (Accessibility APIs etc.),
        // implementing the protocols defined by SuttoOperations.
        .target(
            name: "SuttoInfra",
            dependencies: ["SuttoOperations", "SuttoDomain"]
        ),

        // Everything on screen: AppKit views, windows, and the status item.
        .target(
            name: "SuttoUI",
            dependencies: ["SuttoOperations", "SuttoDomain"]
        ),

        // Composition root: instantiation, wiring, and app lifecycle only.
        .executableTarget(
            name: "SuttoApp",
            dependencies: ["SuttoUI", "SuttoInfra", "SuttoOperations", "SuttoDomain"]
        ),

        .testTarget(
            name: "SuttoDomainTests",
            dependencies: ["SuttoDomain"]
        ),

        .testTarget(
            name: "SuttoOperationsTests",
            dependencies: ["SuttoOperations", "SuttoDomain"]
        ),
    ]
)
