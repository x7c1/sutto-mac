import Testing

@testable import SuttoDomain

@Suite struct KeyComboTests {
    @Test func defaultTogglePanelIsControlOptionSpace() {
        let combo = KeyCombo.defaultTogglePanel

        #expect(combo.keyCode == 49)  // kVK_Space
        #expect(combo.modifiers == [.control, .option])
    }

    @Test func rendersTheDefaultTogglePanelComboForLogs() {
        #expect(KeyCombo.defaultTogglePanel.displayString == "⌃⌥Space")
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
