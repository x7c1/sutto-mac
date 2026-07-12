import Foundation

/// Locations inside the package, derived from this source file's path so the
/// suite finds its binaries no matter which directory `swift test` runs
/// from.
enum E2EPaths {
    /// The package root (the directory containing `Package.swift`).
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Support/
        .deletingLastPathComponent()  // SuttoE2ETests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // package root

    /// The executable inside the bundle assembled by `make app`. `make e2e`
    /// depends on `app`, so the bundle is freshly built from the current
    /// sources by the time the suite runs.
    static let suttoExecutable = packageRoot.appending(
        components: ".build", "Sutto.app", "Contents", "MacOS", "Sutto")

    /// The helper target app. It is a target of this package, so the same
    /// `swift test` invocation that runs this suite builds it (debug
    /// configuration, hence the fixed `.build/debug` path).
    static let targetAppExecutable = packageRoot.appending(
        components: ".build", "debug", "SuttoE2ETargetApp")
}
