import AppKit
import ApplicationServices
import SuttoDomain
import Testing

/// End-to-end space toggling: flip a space's visibility through the
/// settings window's preview — over the Accessibility API, the way the
/// checkbox exposes itself — and observe the layout panel gain or lose
/// that space's miniature on its next open, then restore the original
/// state the same way.
///
/// The settings window exposes each previewed space as one AX checkbox
/// ("Space 1", "Space 2", …) whose value tracks the enabled state; the
/// panel exposes each *enabled* space as an AX group with the same
/// labeling. The scenario counts the panel's space groups before and
/// after the toggle, which observes exactly the row filtering the panel
/// applies.
///
/// The app under test persists into the developer's real collection
/// files, so the scenario restores the flag it flipped — through the UI
/// on the happy path, and through ``CollectionFileStore`` in cleanup when
/// it dies midway.
///
/// Nested inside ``SnapScenarioTests`` so its `.serialized` trait (which
/// applies recursively) also serializes this scenario against the snap
/// scenarios: a sibling suite would run in parallel with them, and every
/// scenario owns the machine-global shortcut.
extension SnapScenarioTests {
    @MainActor
    @Suite struct SpaceToggleScenarioTests {
        /// The Escape key (kVK_Escape), dismissing the panel between opens.
        private static let escapeKey = KeyCombo(keyCode: 53, modifiers: [])

        @Test func togglingASpaceInSettingsRemovesItsMiniatureFromThePanel() async throws {
            try AccessibilityPreflight.requireTrusted()
            try await SuttoUnderTest.terminateStrayInstances()
            try await TargetWindowApp.terminateStrayInstances()

            let sutto = try SuttoUnderTest.launch()
            defer { sutto.terminate() }

            // 1. Open the panel and count its spaces — the baseline the toggle
            // must change. Two spaces minimum keep every later panel state
            // distinguishable from "panel hidden" (zero groups).
            try await openPanel(of: sutto)
            let before = panelSpaceCount(ofPID: sutto.pid)
            try #require(
                before >= 2,
                """
                the active collection shows \(before) space(s); the scenario \
                needs at least 2 to tell a filtered row apart from a hidden \
                panel. Presets satisfy this — re-enable spaces or select \
                another collection.
                """)

            // "Space 1" in the settings preview is the first space of the
            // collection the app resolves, in reading order — pinned via the
            // same on-disk state the app reads.
            let screens = ExpectedFrame.currentScreens()
            let collection = try #require(
                ActivePanelModelReplica.activeCollection(screens: screens))
            let firstSpace = try #require(collection.rows.flatMap(\.spaces).first)

            // Whatever happens below, the developer's file gets the original
            // flag back (redundant after the happy path's own restoration).
            defer {
                CollectionFileStore.restoreSpaceEnabled(
                    collectionId: collection.id, spaceId: firstSpace.id,
                    enabled: firstSpace.enabled)
            }

            // 2. Jump to settings from the open panel (⌘, — the panel hides
            // itself). The window opens on the last-used tab, which may be
            // any of them; the space toggles live on the Layouts tab, so
            // select it explicitly (pressing the already-selected tab is a
            // harmless re-selection) and find the first space's toggle.
            try ShortcutInjector.post(.openSettings)
            let layoutsTab = try await waitFor(
                "the \"Layouts\" toolbar tab in the settings window"
            ) {
                pressable(titled: "Layouts", ofPID: sutto.pid)
            }
            try AXClient.press(layoutsTab)
            let toggle = try await waitFor("the \"Space 1\" toggle in the settings window") {
                spaceToggle(labeled: "Space 1", ofPID: sutto.pid)
            }
            let wasEnabled = AXClient.intValue(of: toggle) == 1
            try #require(
                wasEnabled == firstSpace.enabled,
                "the settings toggle disagrees with the stored collection")

            // 3. Flip it. The settings window re-renders from what was
            // persisted, so the flipped value read back over AX *is* the
            // stored state.
            try AXClient.press(toggle)
            try await waitUntilToggleValue(is: !wasEnabled, ofPID: sutto.pid)

            // 4. The panel reflects the toggle on its next open: one space
            // fewer (or one more, on a machine whose first space started
            // disabled).
            let expectedAfter = wasEnabled ? before - 1 : before + 1
            try ShortcutInjector.post(.defaultTogglePanel)
            try await waitUntil("the panel to show \(expectedAfter) space miniature(s)") {
                panelSpaceCount(ofPID: sutto.pid) == expectedAfter
            }

            // 5. Restore through the same UI: press the toggle again (the
            // settings window is still open behind the panel).
            let restoreToggle = try await waitFor("the \"Space 1\" toggle again") {
                spaceToggle(labeled: "Space 1", ofPID: sutto.pid)
            }
            try AXClient.press(restoreToggle)
            try await waitUntilToggleValue(is: wasEnabled, ofPID: sutto.pid)

            // 6. The still-open panel renders the pre-toggle content until it
            // reopens (the model re-resolves on show); close it and reopen.
            try ShortcutInjector.post(Self.escapeKey)
            try await waitUntil("the panel to hide after Escape") {
                panelSpaceCount(ofPID: sutto.pid) == 0
            }
            try ShortcutInjector.post(.defaultTogglePanel)
            try await waitUntil("the reopened panel to show \(before) space miniature(s)") {
                panelSpaceCount(ofPID: sutto.pid) == before
            }
        }

        // MARK: - Steps

        /// Injects the global shortcut and waits for a space miniature to
        /// become reachable over AX — the same bounded retry as the snap
        /// scenarios, because a keystroke injected before the freshly launched
        /// app registers its hotkey is simply lost.
        private func openPanel(of sutto: SuttoUnderTest) async throws {
            let attempts = 3
            for _ in 0..<attempts {
                try ShortcutInjector.post(.defaultTogglePanel)
                do {
                    try await waitUntil(
                        "a space miniature on the layout panel", timeout: .seconds(2)
                    ) {
                        panelSpaceCount(ofPID: sutto.pid) > 0
                    }
                    return
                } catch {
                    continue
                }
            }
            let combo = KeyCombo.defaultTogglePanel.displayString
            throw E2EFailure(
                """
                no space miniature appeared after \(attempts) injections of \
                \(combo). Likely causes: another app holds the \(combo) hotkey, \
                the panel is not exposed to the Accessibility API — or every \
                space of the active collection is disabled, in which case \
                re-enable one in the settings window first.
                """)
        }

        /// The number of space miniatures the panel currently exposes: the
        /// panel labels them "Space 1" through "Space N" continuously, so the
        /// count is the largest N that resolves. Zero when the panel is hidden
        /// (the settings window's checkboxes expose no such groups).
        private func panelSpaceCount(ofPID pid: pid_t) -> Int {
            let windows = AXClient.windows(ofPID: pid)
            var count = 0
            while windows.contains(where: {
                !AXClient.groups(labeled: "Space \(count + 1)", under: $0).isEmpty
            }) {
                count += 1
            }
            return count
        }

        /// The settings window's toggle checkbox with the given label, in any
        /// of the app's windows — `nil` while none is reachable over AX.
        private func spaceToggle(labeled label: String, ofPID pid: pid_t) -> AXUIElement? {
            AXClient.windows(ofPID: pid).lazy
                .compactMap { AXClient.checkBox(labeled: label, under: $0) }
                .first
        }

        /// A press-capable element with the given title in any of the app's
        /// windows — the settings window's toolbar tabs, here — `nil` while
        /// none is reachable over AX.
        private func pressable(titled title: String, ofPID pid: pid_t) -> AXUIElement? {
            AXClient.windows(ofPID: pid).lazy
                .compactMap { AXClient.pressable(titled: title, under: $0) }
                .first
        }

        /// Waits until the first space's toggle reads the given enabled state.
        /// The toggle is re-found on every poll: each toggle rebuilds the
        /// settings content, so the previously found element goes stale.
        private func waitUntilToggleValue(is enabled: Bool, ofPID pid: pid_t) async throws {
            try await waitUntil("the \"Space 1\" toggle to read \(enabled ? 1 : 0)") {
                spaceToggle(labeled: "Space 1", ofPID: pid)
                    .map { AXClient.intValue(of: $0) == (enabled ? 1 : 0) } ?? false
            }
        }
    }
}
