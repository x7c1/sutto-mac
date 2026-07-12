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
        let combo = KeyCombo(keyCode: 0, modifiers: .command)

        #expect(combo.displayString == "⌘key(0)")
    }

    @Test func rendersAnUnmodifiedKeyWithoutSymbols() {
        let combo = KeyCombo(keyCode: 49, modifiers: [])

        #expect(combo.displayString == "Space")
    }
}
