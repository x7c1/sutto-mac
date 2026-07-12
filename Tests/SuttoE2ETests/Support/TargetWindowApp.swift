import AppKit
import SuttoDomain

/// The disposable window the scenario snaps, provided by the
/// `SuttoE2ETargetApp` helper (see its `main.swift` for why a private helper
/// beats driving TextEdit).
@MainActor
struct TargetWindowApp {
    private let launched: LaunchedProcess

    var pid: pid_t { launched.pid }

    static func launch() throws -> TargetWindowApp {
        TargetWindowApp(launched: try .launch(executable: E2EPaths.targetAppExecutable))
    }

    /// Quits helpers left over from an interrupted earlier run, so no stale
    /// "Sutto E2E Target" window lingers on screen next to the fresh one.
    static func terminateStrayInstances() async throws {
        try await terminateRunningApplications(executableNamed: "SuttoE2ETargetApp")
    }

    /// Waits until the helper is the frontmost application and its window
    /// has AX focus. The helper's self-activation on launch is only advisory
    /// on modern macOS (and routinely refused), so each poll pushes it to
    /// the front through the Accessibility API until the window server
    /// complies — see ``AXClient/makeFrontmost(pid:)``.
    func waitUntilFrontmostWithFocusedWindow() async throws {
        try await waitUntil(
            "the target window app to become frontmost with a focused window",
            timeout: .seconds(10)
        ) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                return focusedWindowFrame() != nil
            }
            _ = AXClient.makeFrontmost(pid: pid)
            return false
        }
    }

    /// The helper's focused-window frame in AX coordinates, read through the
    /// Accessibility API exactly the way Sutto itself will read it.
    func focusedWindowFrame() -> PixelRect? {
        AXClient.focusedWindow(ofPID: pid).flatMap { AXClient.frame(of: $0) }
    }

    func terminate() {
        launched.terminate()
    }
}
