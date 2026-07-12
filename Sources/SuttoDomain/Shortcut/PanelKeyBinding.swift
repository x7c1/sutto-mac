/// What a key press means to the open layout panel's keyboard navigation.
public enum PanelKeyAction: Equatable, Sendable {
    /// Move the focus in an arrow direction.
    case move(MiniaturePanelNavigator.Direction)

    /// Apply the focused region's layout (Return / keypad Enter).
    case activate

    /// Move the focus along the Tab order, wrapping around.
    case cycle(reverse: Bool)
}

/// Maps key combos to panel navigation actions — the key table of the GNOME
/// `MainPanelKeyboardNavigator.handleKeyPress`, as a pure policy so the
/// window's key handling stays a thin switch.
///
/// Bindings, matching GNOME:
///
/// - Arrow keys move the focus. Shift is tolerated (the GNOME navigator
///   reads the key symbol without masking Shift), but Command, Option, and
///   Control combos are *not* navigation — they fall through to whatever
///   else handles them (⌘, opens settings, for example).
/// - Return and keypad Enter activate the focused region.
/// - Tab / Shift+Tab cycle through the regions.
/// - Control+P/N/B/F are the Emacs-style arrow aliases the GNOME navigator
///   ships (its `ctrlKeyMap`), with exactly Control held.
///
/// Escape is deliberately absent: closing the panel predates keyboard
/// navigation and stays on its own `cancelOperation` path.
public enum PanelKeyBinding {
    /// The navigation action for `combo`, or `nil` when the combo means
    /// nothing to the navigator and must not be consumed.
    public static func action(for combo: KeyCombo) -> PanelKeyAction? {
        // Control alone: the GNOME ctrlKeyMap (Emacs-style directions).
        // Any other key with Control is not navigation — GNOME propagates
        // Ctrl+arrows the same way.
        if combo.modifiers == [.control] {
            return switch combo.keyCode {
            case 35: .move(.up)  // kVK_ANSI_P
            case 45: .move(.down)  // kVK_ANSI_N
            case 11: .move(.left)  // kVK_ANSI_B
            case 3: .move(.right)  // kVK_ANSI_F
            default: nil
            }
        }

        guard combo.modifiers.isDisjoint(with: [.command, .option, .control]) else {
            return nil
        }
        return switch combo.keyCode {
        case 123: .move(.left)  // kVK_LeftArrow
        case 124: .move(.right)  // kVK_RightArrow
        case 125: .move(.down)  // kVK_DownArrow
        case 126: .move(.up)  // kVK_UpArrow
        case 36, 76: .activate  // kVK_Return, kVK_ANSI_KeypadEnter
        case 48: .cycle(reverse: combo.modifiers.contains(.shift))  // kVK_Tab
        default: nil
        }
    }
}
