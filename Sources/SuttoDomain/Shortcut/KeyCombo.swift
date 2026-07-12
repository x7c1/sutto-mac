/// A keyboard combination: a virtual key code plus modifier keys.
///
/// The key code uses the macOS virtual key code numbering (the `kVK_*`
/// constants, matching `NSEvent.keyCode`), kept as a plain integer so the
/// domain stays free of macOS framework imports. Translation to the values
/// the hotkey APIs expect lives in the infra layer.
public struct KeyCombo: Equatable, Sendable {
    /// The modifier keys held together with the key.
    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// The macOS virtual key code (`kVK_*` numbering).
    public let keyCode: UInt16
    public let modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

extension KeyCombo {
    /// The default shortcut for toggling the layout panel: Control+Command+O.
    ///
    /// The GNOME version ships with no default (users pick one in its
    /// preferences); the mac app always has a working toggle instead, using
    /// this combo until the user captures another one in Settings (and
    /// restoring it via the Reset button there).
    public static let defaultTogglePanel = KeyCombo(
        keyCode: 31,  // kVK_ANSI_O (the domain cannot import Carbon for the constant)
        modifiers: [.control, .command]
    )

    /// The shortcut that opens the settings window while the layout panel is
    /// visible: Command+Comma.
    ///
    /// The GNOME default is Ctrl+Comma (`open-preferences-shortcut` in its
    /// gschema), but ⌘, is *the* canonical settings shortcut on macOS, so
    /// the mac app deviates deliberately. Unlike GNOME this combo is not
    /// user-configurable yet.
    public static let openSettings = KeyCombo(
        keyCode: 43,  // kVK_ANSI_Comma
        modifiers: [.command]
    )
}

extension KeyCombo {
    /// A human-readable rendering such as "⌃⌥Space", in the conventional
    /// macOS modifier order (control, option, shift, command). Used in logs
    /// and by the settings shortcut-capture field; key codes without a known
    /// name fall back to "key(N)".
    public var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + keyName
    }

    private var keyName: String {
        // The `kVK_*` virtual key codes as raw numbers (the domain cannot
        // import Carbon for the constants). Covers the keys a user can
        // plausibly capture as a shortcut; anything else falls back to
        // "key(N)", which stays unambiguous if ugly.
        switch keyCode {
        case 0: "A"
        case 1: "S"
        case 2: "D"
        case 3: "F"
        case 4: "H"
        case 5: "G"
        case 6: "Z"
        case 7: "X"
        case 8: "C"
        case 9: "V"
        case 11: "B"
        case 12: "Q"
        case 13: "W"
        case 14: "E"
        case 15: "R"
        case 16: "Y"
        case 17: "T"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "="
        case 25: "9"
        case 26: "7"
        case 27: "-"
        case 28: "8"
        case 29: "0"
        case 30: "]"
        case 31: "O"
        case 32: "U"
        case 33: "["
        case 34: "I"
        case 35: "P"
        case 36: "↩"  // Return
        case 37: "L"
        case 38: "J"
        case 39: "'"
        case 40: "K"
        case 41: ";"
        case 42: "\\"
        case 43: ","
        case 44: "/"
        case 45: "N"
        case 46: "M"
        case 47: "."
        case 48: "⇥"  // Tab
        case 49: "Space"
        case 50: "`"
        case 51: "⌫"  // Delete (backspace)
        case 53: "⎋"  // Escape
        case 96: "F5"
        case 97: "F6"
        case 98: "F7"
        case 99: "F3"
        case 100: "F8"
        case 101: "F9"
        case 103: "F11"
        case 105: "F13"
        case 107: "F14"
        case 109: "F10"
        case 111: "F12"
        case 113: "F15"
        case 115: "↖"  // Home
        case 116: "⇞"  // Page Up
        case 117: "⌦"  // Forward Delete
        case 118: "F4"
        case 119: "↘"  // End
        case 120: "F2"
        case 121: "⇟"  // Page Down
        case 122: "F1"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: "key(\(keyCode))"
        }
    }
}
