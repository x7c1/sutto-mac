import AppKit

/// A process the e2e suite launched, with teardown that works even when the
/// test body failed halfway: call `terminate()` from a `defer` right after
/// launching.
///
/// Launching happens with `Process` (plain fork/exec) rather than
/// `NSWorkspace`, deliberately: a fork/exec'd child keeps the terminal that
/// runs `make e2e` as its TCC "responsible process", so the test runner's
/// event injection and the spawned Sutto's AX calls are all covered by the
/// terminal's single Accessibility grant. Launching through
/// NSWorkspace/LaunchServices would make Sutto its own responsible process
/// and require a separate grant keyed to the bundle's code signature — one
/// that an unsigned development build loses on every rebuild.
@MainActor
final class LaunchedProcess {
    private let process: Process

    var pid: pid_t { process.processIdentifier }

    private init(process: Process) {
        self.process = process
    }

    static func launch(executable: URL) throws -> LaunchedProcess {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw E2EFailure(
                """
                missing executable at \(executable.path) — run the suite \
                through `make e2e`, which builds it first
                """)
        }
        let process = Process()
        process.executableURL = executable
        try process.run()
        return LaunchedProcess(process: process)
    }

    /// Terminates the process: SIGTERM, a bounded wait, then SIGKILL if it
    /// is still alive. Synchronous so it can run in a `defer`.
    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<40 where process.isRunning {
            usleep(50_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

/// Force-quits every running application whose executable has the given
/// name, and waits until they are gone. Used to clear instances that this
/// suite did not launch itself — leftovers from `make run` or from an
/// interrupted earlier run — which its per-process `terminate()` teardown
/// cannot reach.
@MainActor
func terminateRunningApplications(executableNamed name: String) async throws {
    func running() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.executableURL?.lastPathComponent == name
        }
    }
    for app in running() {
        app.forceTerminate()
    }
    try await waitUntil("stray \(name) instances to quit") { running().isEmpty }
}
