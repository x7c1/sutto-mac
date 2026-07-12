import AppKit

/// The Sutto instance under test: the freshly assembled `.build/Sutto.app`
/// bundle, launched as a child of the test runner.
@MainActor
struct SuttoUnderTest {
    private let launched: LaunchedProcess

    var pid: pid_t { launched.pid }

    static func launch() throws -> SuttoUnderTest {
        SuttoUnderTest(launched: try .launch(executable: E2EPaths.suttoExecutable))
    }

    /// Quits Sutto instances left over from `make run` or an interrupted
    /// earlier e2e run. Two live instances would race for the global
    /// shortcut — the loser's registration fails, and the panel would appear
    /// in whichever process registered first, not necessarily ours.
    static func terminateStrayInstances() async throws {
        try await terminateRunningApplications(executableNamed: "Sutto")
    }

    func terminate() {
        launched.terminate()
    }
}
