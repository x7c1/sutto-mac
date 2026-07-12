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
    /// The provisional default shortcut for toggling the layout panel:
    /// Control+Option+Space.
    ///
    /// The GNOME version ships with no default (users pick one in its
    /// preferences), but the macOS settings screen only arrives in v0.2, so
    /// v0.1 hardcodes this combo. The v0.2 shortcut-capture UI replaces this
    /// constant with a user-configurable value.
    public static let defaultTogglePanel = KeyCombo(
        keyCode: 31,  // kVK_ANSI_O (the domain cannot import Carbon for the constant)
        modifiers: [.control, .command]
    )
}

extension KeyCombo {
    /// A human-readable rendering such as "⌃⌥Space", in the conventional
    /// macOS modifier order (control, option, shift, command). Intended for
    /// logs; key codes without a known name fall back to "key(N)".
    public var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + keyName
    }

    private var keyName: String {
        // Only the keys Sutto actually uses are named; extend as needed.
        switch keyCode {
        case 31: "O"
        case 49: "Space"
        default: "key(\(keyCode))"
        }
    }
}
