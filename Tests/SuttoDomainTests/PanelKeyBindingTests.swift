import Testing

@testable import SuttoDomain

/// The key table of the GNOME `MainPanelKeyboardNavigator.handleKeyPress`:
/// arrows (Shift tolerated), Return / keypad Enter, Tab / Shift+Tab, and
/// the Emacs-style Control aliases; everything else is not navigation and
/// must not be consumed.
@Suite struct PanelKeyBindingTests {
    private func combo(_ keyCode: UInt16, _ modifiers: KeyCombo.Modifiers = []) -> KeyCombo {
        KeyCombo(keyCode: keyCode, modifiers: modifiers)
    }

    @Test func arrowsMoveTheFocus() {
        #expect(PanelKeyBinding.action(for: combo(123)) == .move(.left))
        #expect(PanelKeyBinding.action(for: combo(124)) == .move(.right))
        #expect(PanelKeyBinding.action(for: combo(125)) == .move(.down))
        #expect(PanelKeyBinding.action(for: combo(126)) == .move(.up))
    }

    /// The GNOME navigator reads the key symbol without masking Shift, so
    /// a Shift-arrow still navigates.
    @Test func shiftedArrowsStillMove() {
        #expect(PanelKeyBinding.action(for: combo(124, [.shift])) == .move(.right))
    }

    @Test func returnAndKeypadEnterActivate() {
        #expect(PanelKeyBinding.action(for: combo(36)) == .activate)
        #expect(PanelKeyBinding.action(for: combo(76)) == .activate)
    }

    @Test func tabCyclesAndShiftTabReverses() {
        #expect(PanelKeyBinding.action(for: combo(48)) == .cycle(reverse: false))
        #expect(PanelKeyBinding.action(for: combo(48, [.shift])) == .cycle(reverse: true))
    }

    /// GNOME's `ctrlKeyMap`: Control+P/N/B/F as arrow aliases, with
    /// exactly Control held.
    @Test func controlLetterAliasesMove() {
        #expect(PanelKeyBinding.action(for: combo(35, [.control])) == .move(.up))
        #expect(PanelKeyBinding.action(for: combo(45, [.control])) == .move(.down))
        #expect(PanelKeyBinding.action(for: combo(11, [.control])) == .move(.left))
        #expect(PanelKeyBinding.action(for: combo(3, [.control])) == .move(.right))
        #expect(PanelKeyBinding.action(for: combo(35, [.control, .shift])) == nil)
    }

    /// Command, Option, or Control combos are not navigation: ⌘, must keep
    /// opening settings, and Control-arrows propagate exactly as in GNOME
    /// (its ctrlKeyMap has no arrow entries).
    @Test func modifiedCombosAreNotConsumed() {
        #expect(PanelKeyBinding.action(for: combo(124, [.command])) == nil)
        #expect(PanelKeyBinding.action(for: combo(124, [.option])) == nil)
        #expect(PanelKeyBinding.action(for: combo(124, [.control])) == nil)
        #expect(PanelKeyBinding.action(for: combo(43, [.command])) == nil)  // ⌘,
        #expect(PanelKeyBinding.action(for: combo(36, [.command])) == nil)  // ⌘↩
    }

    @Test func unrelatedKeysAreNotConsumed() {
        #expect(PanelKeyBinding.action(for: combo(53)) == nil)  // Escape
        #expect(PanelKeyBinding.action(for: combo(49)) == nil)  // Space
        #expect(PanelKeyBinding.action(for: combo(35)) == nil)  // plain P
    }
}
