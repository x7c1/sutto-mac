import AppKit
import ApplicationServices
import SuttoDomain
import Testing

/// End-to-end scenarios driving the real `Sutto.app` from the outside: a
/// global-shortcut keystroke goes in, and a real window's AX frame is what
/// comes out. Local-only — the suite needs the TCC Accessibility permission
/// and is excluded from `make test`; run it with `make e2e`
/// (docs/guides/testing.md, "End-to-end tests").
///
/// Serialized: every scenario owns the machine's frontmost-app state and the
/// global shortcut, so two of them cannot overlap.
@MainActor
@Suite(.serialized)
struct SnapScenarioTests {
    /// Tolerance for comparing AX read-back frames against computed ones,
    /// in pixels. Zero: on the machines this ran on so far, the frame the
    /// helper window settles on matches the resolver's output exactly.
    /// Widen (and document why) only if a real deviation demands it.
    private static let frameTolerance = 0.0

    @Test func snapsTheFrontmostWindowToLeftHalf() async throws {
        try AccessibilityPreflight.requireTrusted()
        try await SuttoUnderTest.terminateStrayInstances()
        try await TargetWindowApp.terminateStrayInstances()

        let sutto = try SuttoUnderTest.launch()
        defer { sutto.terminate() }
        let target = try TargetWindowApp.launch()
        defer { target.terminate() }

        // Sutto's placement targets the frontmost app's focused window, so
        // the helper must be frontmost before the shortcut fires.
        try await target.waitUntilFrontmostWithFocusedWindow()

        let leftHalf = try presetLayout(labeled: "Left Half")
        let button = try await panelButton(labeled: leftHalf.label, in: sutto)

        let before = try await waitFor("the target window's frame") {
            target.focusedWindowFrame()
        }
        let expected = try ExpectedFrame.resolve(leftHalf, windowFrame: before)
        try #require(
            !before.isApproximately(expected, tolerance: Self.frameTolerance),
            """
            the target window already starts on the expected frame \
            \(expected) — the scenario would pass without any movement
            """)

        try AXClient.press(button)

        do {
            try await waitUntil("the target window to land on \(expected)") {
                target.focusedWindowFrame()?
                    .isApproximately(expected, tolerance: Self.frameTolerance) ?? false
            }
        } catch {
            let actual = target.focusedWindowFrame().map(String.init(describing:))
            throw E2EFailure(
                """
                the target window did not land on the expected frame \
                \(expected); last observed frame: \(actual ?? "unreadable"). \
                If it did not move at all, check Sutto's own log: \
                `log show --info --last 2m --predicate 'process == "Sutto" \
                AND subsystem == "io.github.x7c1.SuttoMac"' --style compact`
                """)
        }

        // Selecting a layout also hides the panel; verify the loop closed.
        try await waitUntil("the layout panel to hide after the selection") {
            AXClient.windows(ofPID: sutto.pid).allSatisfy {
                AXClient.button(titled: leftHalf.label, under: $0) == nil
            }
        }
    }

    // MARK: - Steps

    /// Injects the global shortcut and waits for the panel button to become
    /// reachable over AX. The injection is retried a few times because there
    /// is no signal for when the freshly launched Sutto has finished
    /// registering its Carbon hotkey — a keystroke injected before that is
    /// simply lost. Retrying while the button is still absent is safe: the
    /// shortcut toggles the panel, so a lost press and a
    /// not-yet-registered press look identical (no panel, no button).
    private func panelButton(
        labeled label: String, in sutto: SuttoUnderTest
    ) async throws -> AXUIElement {
        let attempts = 3
        for _ in 0..<attempts {
            try ShortcutInjector.post(.defaultTogglePanel)
            do {
                return try await waitFor(
                    "the \"\(label)\" button on the layout panel", timeout: .seconds(2)
                ) {
                    AXClient.windows(ofPID: sutto.pid).lazy
                        .compactMap { AXClient.button(titled: label, under: $0) }
                        .first
                }
            } catch {
                continue
            }
        }
        let combo = KeyCombo.defaultTogglePanel.displayString
        throw E2EFailure(
            """
            the layout panel's "\(label)" button did not appear after \
            \(attempts) injections of \(combo). Likely causes: another app \
            holds the \(combo) hotkey (Sutto's registration then fails — \
            check its log), or the panel is not exposed to the Accessibility \
            API.
            """)
    }

    /// A layout from the generated presets, by label. The generator mints
    /// fresh ids per call, but only the expressions matter here — the
    /// expected frame is resolved from them. "Left Half" (vertical 2-split)
    /// is part of both the standard and the wide preset flavor, so the
    /// button exists no matter which preset the app resolves for the
    /// machine's actual display.
    private func presetLayout(labeled label: String) throws -> Layout {
        let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)
        guard
            let layout = LayoutPanelProjection.layoutGroups(in: preset)
                .flatMap(\.layouts)
                .first(where: { $0.label == label })
        else {
            throw E2EFailure("no preset layout labeled \"\(label)\"")
        }
        return layout
    }
}
