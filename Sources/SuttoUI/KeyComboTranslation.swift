import AppKit
import SuttoDomain

/// Translates AppKit key events into domain ``SuttoDomain/KeyCombo``
/// values, so views can hand key presses to domain policies (shortcut
/// capture, the open-settings check) without AppKit types crossing the
/// layer boundary.
enum KeyComboTranslation {
    static func combo(from event: NSEvent) -> KeyCombo {
        KeyCombo(keyCode: event.keyCode, modifiers: modifiers(from: event.modifierFlags))
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
        let device = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: KeyCombo.Modifiers = []
        if device.contains(.control) { modifiers.insert(.control) }
        if device.contains(.option) { modifiers.insert(.option) }
        if device.contains(.shift) { modifiers.insert(.shift) }
        if device.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
