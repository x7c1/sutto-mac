import Testing

@testable import SuttoDomain

@Suite struct ShortcutCapturePolicyTests {
    @Test func capturesAModifiedKey() {
        let outcome = ShortcutCapturePolicy.outcome(
            forKeyCode: 40, modifiers: [.control, .command])  // ⌃⌘K

        #expect(
            outcome
                == .captured(KeyCombo(keyCode: 40, modifiers: [.control, .command])))
    }

    /// One modifier is enough — GNOME's capture accepts any non-empty
    /// modifier mask, including Shift alone.
    @Test(arguments: [
        KeyCombo.Modifiers.command,
        KeyCombo.Modifiers.control,
        KeyCombo.Modifiers.option,
        KeyCombo.Modifiers.shift,
    ])
    func aSingleModifierSuffices(modifier: KeyCombo.Modifiers) {
        let outcome = ShortcutCapturePolicy.outcome(forKeyCode: 40, modifiers: modifier)

        #expect(outcome == .captured(KeyCombo(keyCode: 40, modifiers: modifier)))
    }

    /// Combos the app's main menu also claims (⌘W Close, ⌘Q Quit) are
    /// ordinary capturable shortcuts to the policy — the capture field
    /// intercepts them ahead of the menu (`performKeyEquivalent` runs on
    /// the view hierarchy before AppKit consults `NSApp.mainMenu`), so
    /// the policy must accept rather than special-case them.
    @Test(arguments: [UInt16(13), 12])  // kVK_ANSI_W, kVK_ANSI_Q
    func capturesCombosTheMainMenuAlsoClaims(keyCode: UInt16) {
        let outcome = ShortcutCapturePolicy.outcome(forKeyCode: keyCode, modifiers: .command)

        #expect(outcome == .captured(KeyCombo(keyCode: keyCode, modifiers: .command)))
    }

    /// A key without any modifier would shadow plain typing; wait for a
    /// real combo instead (the GNOME dialog ignores these the same way).
    @Test func ignoresAnUnmodifiedKey() {
        let outcome = ShortcutCapturePolicy.outcome(forKeyCode: 40, modifiers: [])

        #expect(outcome == .ignored)
    }

    /// Pressing a modifier key by itself is never a shortcut — covering
    /// both hands' variants plus Caps Lock and Fn.
    @Test(arguments: [UInt16(54), 55, 56, 57, 58, 59, 60, 61, 62, 63])
    func ignoresBareModifierKeys(keyCode: UInt16) {
        let outcome = ShortcutCapturePolicy.outcome(forKeyCode: keyCode, modifiers: [])

        #expect(outcome == .ignored)
    }

    /// A modifier key code stays ignored even when the event carries its
    /// own flag (holding ⌘ reports the ⌘ flag with the ⌘ key code).
    @Test func ignoresAModifierKeyCarryingItsOwnFlag() {
        let outcome = ShortcutCapturePolicy.outcome(forKeyCode: 55, modifiers: [.command])

        #expect(outcome == .ignored)
    }

    @Test func escapeCancelsCapture() {
        let outcome = ShortcutCapturePolicy.outcome(forKeyCode: 53, modifiers: [])

        #expect(outcome == .cancelled)
    }

    /// GNOME cancels on Escape before looking at modifiers; mirrored, so
    /// no Escape-based combo can be captured.
    @Test func escapeCancelsEvenWithModifiers() {
        let outcome = ShortcutCapturePolicy.outcome(
            forKeyCode: 53, modifiers: [.control, .command])

        #expect(outcome == .cancelled)
    }
}
