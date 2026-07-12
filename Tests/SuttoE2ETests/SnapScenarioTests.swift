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
/// The panel renders miniature space previews: each space is an AX group
/// ("Space 1", …) containing one group per display ("Display 1", …), whose
/// layout regions are AX buttons titled with their layout label. The
/// scenarios navigate that structure — a region is found *inside a specific
/// display's miniature*, which is what makes cross-monitor placement
/// testable: pressing a region under "Display 2" must move the window to
/// the second screen.
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

    /// The AX label of the primary display's miniature (display key "0").
    private static let primaryDisplayLabel = "Display 1"

    /// The AX label of the second display's miniature (display key "1").
    private static let secondaryDisplayLabel = "Display 2"

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
        let button = try await panelRegion(
            labeled: leftHalf.label, inDisplay: Self.primaryDisplayLabel, of: sutto)

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

    /// Cross-monitor placement: pressing a region inside the *second*
    /// display's miniature moves the window to the second screen, wherever
    /// the window was. Runs only on machines with at least two displays —
    /// with one display the panel renders no clickable "Display 2"
    /// miniature, so there is nothing to drive.
    @Test func snapsToTheSecondDisplayFromItsMiniature() async throws {
        try AccessibilityPreflight.requireTrusted()
        guard NSScreen.screens.count >= 2 else {
            // Single-display machine: cross-monitor placement is not
            // exercisable here. Deliberately pass instead of failing so
            // `make e2e` stays runnable on laptops on the go.
            return
        }
        try await SuttoUnderTest.terminateStrayInstances()
        try await TargetWindowApp.terminateStrayInstances()

        let sutto = try SuttoUnderTest.launch()
        defer { sutto.terminate() }
        let target = try TargetWindowApp.launch()
        defer { target.terminate() }

        try await target.waitUntilFrontmostWithFocusedWindow()

        let leftHalf = try presetLayout(labeled: "Left Half")
        let button = try await panelRegion(
            labeled: leftHalf.label, inDisplay: Self.secondaryDisplayLabel, of: sutto)

        let expected = try ExpectedFrame.resolve(leftHalf, onScreenAt: 1)
        let before = try await waitFor("the target window's frame") {
            target.focusedWindowFrame()
        }
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
                the target window did not land on the second display's \
                expected frame \(expected); last observed frame: \
                \(actual ?? "unreadable"). If it did not move at all, check \
                Sutto's own log: `log show --info --last 2m --predicate \
                'process == "Sutto" AND subsystem == \
                "io.github.x7c1.SuttoMac"' --style compact`
                """)
        }
    }

    /// Keyboard operation end to end: open the panel with the shortcut,
    /// walk the focus with arrow keys, and apply with Return — no mouse,
    /// no AX press. The expectation is *predicted* by the same domain code
    /// the app runs: the scenario rebuilds the panel model the app is
    /// rendering (``ActivePanelModelReplica`` resolves the same collection
    /// from the app's on-disk state), drives a
    /// ``SuttoDomain/MiniaturePanelNavigator`` through the same key
    /// sequence it injects (first arrow establishes focus top-left, second
    /// moves right — or stays, on a panel with nothing to the right), and
    /// asserts the window lands on the frame of whatever region that
    /// simulation says Return applies, on the display the region's
    /// miniature names.
    @Test func snapsViaKeyboardNavigation() async throws {
        try AccessibilityPreflight.requireTrusted()
        try await SuttoUnderTest.terminateStrayInstances()
        try await TargetWindowApp.terminateStrayInstances()

        let sutto = try SuttoUnderTest.launch()
        defer { sutto.terminate() }
        let target = try TargetWindowApp.launch()
        defer { target.terminate() }

        try await target.waitUntilFrontmostWithFocusedWindow()

        // Opens the panel and confirms it is on screen (a known region is
        // reachable over AX); the panel is the key window from here on.
        let leftHalf = try presetLayout(labeled: "Left Half")
        _ = try await panelRegion(
            labeled: leftHalf.label, inDisplay: Self.primaryDisplayLabel, of: sutto)

        // Predict the outcome with the app's own domain math, on the
        // collection the app actually resolved.
        let screens = ExpectedFrame.currentScreens()
        let navigator = MiniaturePanelNavigator(
            model: try ActivePanelModelReplica.panelModel(screens: screens))
        let established = try #require(
            navigator.move(from: nil, direction: .right),
            "the rendered panel has no focusable region")
        let focused = navigator.move(from: established, direction: .right) ?? established
        let selection = try #require(navigator.selection(at: focused))
        let screenIndex = try #require(PanelDisplayKey.screenIndex(for: selection.displayKey))
        let expected = try ExpectedFrame.resolve(selection.layout, onScreenAt: screenIndex)

        let before = try await waitFor("the target window's frame") {
            target.focusedWindowFrame()
        }
        try #require(
            !before.isApproximately(expected, tolerance: Self.frameTolerance),
            """
            the target window already starts on the expected frame \
            \(expected) — the scenario would pass without any movement
            """)

        // → establishes focus (top-left), → moves right, ↩ applies.
        let rightArrow = KeyCombo(keyCode: 124, modifiers: [])
        let returnKey = KeyCombo(keyCode: 36, modifiers: [])
        try ShortcutInjector.post(rightArrow)
        try ShortcutInjector.post(rightArrow)
        try ShortcutInjector.post(returnKey)

        do {
            try await waitUntil("the target window to land on \(expected)") {
                target.focusedWindowFrame()?
                    .isApproximately(expected, tolerance: Self.frameTolerance) ?? false
            }
        } catch {
            let actual = target.focusedWindowFrame().map(String.init(describing:))
            throw E2EFailure(
                """
                the target window did not land on the keyboard-selected \
                frame \(expected) (layout "\(selection.layout.label)" on \
                display key \(selection.displayKey)); last observed frame: \
                \(actual ?? "unreadable"). If it did not move at all, the \
                key events may not have reached the panel — check Sutto's \
                log: `log show --info --last 2m --predicate 'process == \
                "Sutto" AND subsystem == "io.github.x7c1.SuttoMac"' \
                --style compact`
                """)
        }

        // Return applies through the click path, which also hides the
        // panel; verify the loop closed.
        try await waitUntil("the layout panel to hide after the selection") {
            AXClient.windows(ofPID: sutto.pid).allSatisfy {
                AXClient.button(titled: selection.layout.label, under: $0) == nil
            }
        }
    }

    // MARK: - Steps

    /// Injects the global shortcut and waits for a layout region to become
    /// reachable over AX, inside the miniature of the display with the
    /// given AX label (any space's). The injection is retried a few times
    /// because there is no signal for when the freshly launched Sutto has
    /// finished registering its Carbon hotkey — a keystroke injected before
    /// that is simply lost. Retrying while the region is still absent is
    /// safe: the shortcut toggles the panel, so a lost press and a
    /// not-yet-registered press look identical (no panel, no region).
    private func panelRegion(
        labeled label: String, inDisplay displayLabel: String, of sutto: SuttoUnderTest
    ) async throws -> AXUIElement {
        let attempts = 3
        for _ in 0..<attempts {
            try ShortcutInjector.post(.defaultTogglePanel)
            do {
                return try await waitFor(
                    "the \"\(label)\" region in \"\(displayLabel)\" on the layout panel",
                    timeout: .seconds(2)
                ) {
                    AXClient.windows(ofPID: sutto.pid).lazy
                        .compactMap { window in
                            AXClient.groups(labeled: displayLabel, under: window).lazy
                                .compactMap { AXClient.button(titled: label, under: $0) }
                                .first
                        }
                        .first
                }
            } catch {
                continue
            }
        }
        let combo = KeyCombo.defaultTogglePanel.displayString
        throw E2EFailure(
            """
            the layout panel's "\(label)" region in "\(displayLabel)" did \
            not appear after \(attempts) injections of \(combo). Likely \
            causes: another app holds the \(combo) hotkey (Sutto's \
            registration then fails — check its log), or the panel is not \
            exposed to the Accessibility API.
            """)
    }

    /// A layout from the generated presets, by label. The generator mints
    /// fresh ids per call, but only the expressions matter here — the
    /// expected frame is resolved from them. "Left Half" (vertical 2-split)
    /// is part of both the standard and the wide preset flavor, so the
    /// region exists no matter which preset the app resolves for the
    /// machine's actual displays.
    private func presetLayout(labeled label: String) throws -> Layout {
        let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)
        guard
            let layout = preset.rows
                .flatMap(\.spaces)
                .compactMap({ $0.displays[PanelDisplayKey.primary] })
                .flatMap(\.layouts)
                .first(where: { $0.label == label })
        else {
            throw E2EFailure("no preset layout labeled \"\(label)\"")
        }
        return layout
    }
}
