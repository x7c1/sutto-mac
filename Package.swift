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

        // Fixtures/ holds real sample collection JSON vendored from the
        // GNOME version's docs/examples/, used to pin cross-OS schema
        // compatibility — see LayoutConfigurationCodecTests.
        .testTarget(
            name: "SuttoDomainTests",
            dependencies: ["SuttoDomain"],
            resources: [.copy("Fixtures")]
        ),

        .testTarget(
            name: "SuttoOperationsTests",
            dependencies: ["SuttoOperations", "SuttoDomain"]
        ),

        // Covers the Foundation-only infra adapters (file persistence,
        // UserDefaults) against temp directories and isolated defaults
        // suites -- no Accessibility APIs involved, so these run in CI like
        // the other unit tests. The AX-backed adapters are exercised by the
        // e2e suite instead.
        .testTarget(
            name: "SuttoInfraTests",
            dependencies: ["SuttoInfra", "SuttoOperations", "SuttoDomain"]
        ),

        // Local-only end-to-end suite: launches the real Sutto.app bundle and
        // drives it from the outside (event injection + Accessibility API).
        // Needs the TCC Accessibility permission, so `make test` skips it and
        // `make e2e` runs it — see docs/guides/testing.md. Depends on
        // SuttoDomain only (shared constants and frame math): the harness
        // must observe the app like an external tool, not reach into
        // SuttoInfra/SuttoUI internals.
        .testTarget(
            name: "SuttoE2ETests",
            dependencies: ["SuttoDomain"]
        ),

        // A minimal window-owning app that the e2e suite launches as its
        // placement target. Test-only, hence under Tests/ despite being an
        // executable target.
        .executableTarget(
            name: "SuttoE2ETargetApp",
            path: "Tests/SuttoE2ETargetApp"
        ),
    ]
)
