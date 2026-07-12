import Testing

@testable import SuttoDomain

@Suite struct KeyComboTests {
    @Test func defaultTogglePanelIsControlCommandO() {
        let combo = KeyCombo.defaultTogglePanel

        #expect(combo.keyCode == 31)  // kVK_ANSI_O
        #expect(combo.modifiers == [.control, .command])
    }

    @Test func rendersTheDefaultTogglePanelComboForLogs() {
        #expect(KeyCombo.defaultTogglePanel.displayString == "⌃⌘O")
    }

    @Test func rendersModifiersInConventionalMacOrder() {
        let combo = KeyCombo(
            keyCode: 49,
            modifiers: [.command, .shift, .option, .control]
        )

        #expect(combo.displayString == "⌃⌥⇧⌘Space")
    }

    @Test func fallsBackToTheNumericCodeForUnnamedKeys() {
        let combo = KeyCombo(keyCode: 255, modifiers: .command)

        #expect(combo.displayString == "⌘key(255)")
    }

    @Test func rendersAnUnmodifiedKeyWithoutSymbols() {
        let combo = KeyCombo(keyCode: 49, modifiers: [])

        #expect(combo.displayString == "Space")
    }

    /// ⌘, — the macOS settings convention. The GNOME default is Ctrl+Comma;
    /// the modifier deviation is deliberate.
    @Test func openSettingsIsCommandComma() {
        let combo = KeyCombo.openSettings

        #expect(combo.keyCode == 43)  // kVK_ANSI_Comma
        #expect(combo.modifiers == [.command])
        #expect(combo.displayString == "⌘,")
    }

    /// A sampling of the key-name table across its ranges: letters, digits,
    /// punctuation, arrows, and function keys — what a captured shortcut
    /// shows in the settings field.
    @Test(arguments: [
        (UInt16(0), "A"),
        (UInt16(40), "K"),
        (UInt16(18), "1"),
        (UInt16(47), "."),
        (UInt16(36), "↩"),
        (UInt16(123), "←"),
        (UInt16(122), "F1"),
    ])
    func namesCapturableKeys(keyCode: UInt16, name: String) {
        let combo = KeyCombo(keyCode: keyCode, modifiers: [])

        #expect(combo.displayString == name)
    }
}
