import CoreGraphics
import SuttoDomain

/// Posts a ``KeyCombo`` to the system HID event stream, as if the user had
/// typed it. Requires the Accessibility permission.
@MainActor
enum ShortcutInjector {
    static func post(_ combo: KeyCombo) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
            let keyUp = CGEvent(
                keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false)
        else {
            throw E2EFailure("could not create keyboard events for \(combo.displayString)")
        }
        keyDown.flags = combo.modifiers.eventFlags
        keyUp.flags = combo.modifiers.eventFlags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

extension KeyCombo.Modifiers {
    /// The CGEvent flag set for these modifiers — the event-injection
    /// counterpart of the Carbon translation in `SuttoInfra`.
    fileprivate var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}
