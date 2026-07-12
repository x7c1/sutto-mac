/// What the shortcut-capture field should do with one key press.
public enum ShortcutCaptureOutcome: Equatable, Sendable {
    /// The press is a valid shortcut; adopt it.
    case captured(KeyCombo)

    /// The press asked to leave capture mode without changing anything.
    case cancelled

    /// The press cannot be a shortcut on its own (a bare modifier, or a key
    /// without any modifier); stay in capture mode and wait for more input.
    case ignored
}

/// Decides how the settings shortcut-capture field responds to a key press.
///
/// Mirrors the capture dialog of the GNOME version
/// (`prefs/keyboard-shortcuts.ts`): Escape cancels, pure modifier presses
/// are ignored, and a key without at least one modifier is ignored too —
/// a global shortcut needs a modifier or it would shadow plain typing.
///
/// One GNOME behavior is deliberately not mirrored: its BackSpace-to-clear
/// leaves the shortcut *disabled* (GNOME ships with no default), while the
/// mac app always keeps a working toggle shortcut — clearing is replaced by
/// the Reset-to-default button next to the capture field.
public enum ShortcutCapturePolicy {
    /// The `kVK_*` codes of the modifier keys themselves (Command, Shift,
    /// Caps Lock, Option, Control, right-hand variants, and Fn). Pressing
    /// one alone is never a shortcut.
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// The `kVK_Escape` code; Escape (with any modifiers) cancels capture,
    /// exactly like the GNOME dialog.
    private static let escapeKeyCode: UInt16 = 53

    public static func outcome(
        forKeyCode keyCode: UInt16, modifiers: KeyCombo.Modifiers
    ) -> ShortcutCaptureOutcome {
        if keyCode == escapeKeyCode {
            return .cancelled
        }
        if modifierKeyCodes.contains(keyCode) {
            return .ignored
        }
        if modifiers.isEmpty {
            return .ignored
        }
        return .captured(KeyCombo(keyCode: keyCode, modifiers: modifiers))
    }
}
