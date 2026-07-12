/// A layout choice made in the panel: which layout, and on which display's
/// miniature it was clicked.
///
/// Mirrors `LayoutSelectedEvent` in `domain/layout/types.ts` of the GNOME
/// version (`monitorKey` there, `displayKey` here — matching how
/// ``Space/displays`` names its keys). The display key is what lets the
/// placement path target the clicked display rather than the window's own
/// screen; see ``PanelDisplayKey`` for how keys map to actual screens.
public struct LayoutSelectedEvent: Equatable, Sendable {
    /// The layout the user picked.
    public let layout: Layout

    /// The display key of the miniature the layout was clicked on
    /// (`"0"`, `"1"`, …).
    public let displayKey: String

    public init(layout: Layout, displayKey: String) {
        self.layout = layout
        self.displayKey = displayKey
    }
}

/// The mapping between collection display keys (`"0"`, `"1"`, …) and actual
/// screens.
///
/// A display key is the *index into the screen list* the app renders and
/// places on: key `"N"` means the N-th screen of ``…/ScreenProviding``'s
/// order, which is `NSScreen.screens` order — the primary screen (the one
/// whose bottom-left corner is the global AppKit origin) first. The GNOME
/// version keys displays by Mutter's monitor index the same way
/// (`String(monitor.index)` in its monitor provider, index 0 being the
/// primary); both apps therefore agree that `"0"` is the primary display,
/// which is what keeps exported collections meaningful across the two.
public enum PanelDisplayKey {
    /// The display key of the primary screen.
    public static let primary = "0"

    /// The key for the screen at `index` in the provider's screen order.
    public static func key(forScreenAt index: Int) -> String {
        String(index)
    }

    /// The screen index a display key refers to, or `nil` when the key is
    /// not a whole number (collections are user-editable JSON, so a
    /// malformed key must not crash the panel).
    public static func screenIndex(for key: String) -> Int? {
        Int(key)
    }
}
