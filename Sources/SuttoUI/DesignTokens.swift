import AppKit

/// The one place where the UI's visual decisions live: colors, corner
/// radii, border widths, font sizes, and spacing for both the layout panel
/// and the settings window. Tweaking the look of either surface should be
/// a matter of editing values here, not hunting literals across views.
///
/// Two vocabularies meet in this file, deliberately kept apart:
///
/// - ``PanelPalette``/``PanelMetrics`` carry the *panel's* visual identity,
///   ported from the GNOME version's stylesheet vocabulary
///   (`ui/constants.ts` and the inline styles in `ui/components/*.ts`).
///   The panel should feel like Sutto on any platform, so these are fixed
///   values, not system colors — with macOS conventions kept where they
///   conflict (the vibrancy material stays, for example).
/// - ``SettingsMetrics`` carries the *settings window's* rhythm, which
///   follows the macOS HIG instead: system semantic colors only (defined
///   at the point of use, since AppKit provides them), an 8-point spacing
///   grid, and standard control sizing.
///
/// Geometry that the domain shares with keyboard navigation (miniature
/// sizes, space/row spacing, content insets) is *not* here — it lives in
/// `SuttoDomain.MiniaturePanelModel.Metrics`, because the navigator must
/// traverse exactly the geometry the panel draws. This file only holds
/// values that are free to change without touching behavior.

/// Fixed colors for the layout panel and its miniatures. The panel
/// background is an `NSVisualEffectView` with the `hudWindow` material,
/// which is dark in both system appearances, so these do not react to the
/// appearance — the same fixed dark palette the GNOME panel uses
/// (`ui/constants.ts`). Each constant names its GNOME counterpart.
enum PanelPalette {
    /// A space miniature's fill (GNOME `MINIATURE_SPACE_BG_COLOR`,
    /// a raised gray over the panel background). Translucent white rather
    /// than opaque gray so the vibrancy material shows through.
    static let spaceBackground = NSColor.white.withAlphaComponent(0.08)

    /// A display miniature's fill (GNOME `DISPLAY_BG_COLOR`, near-black —
    /// clearly darker than the space it sits on).
    static let displayBackground = NSColor.black.withAlphaComponent(0.35)

    /// Layout region fill (GNOME `BUTTON_BG_COLOR`).
    static let regionBackground = NSColor.white.withAlphaComponent(0.15)

    /// Layout region fill on hover (GNOME `BUTTON_BG_COLOR_HOVER`).
    static let regionBackgroundHovered = NSColor.white.withAlphaComponent(0.30)

    /// Layout region border (GNOME `BUTTON_BORDER_COLOR`,
    /// rgba(255,255,255,0.3)).
    static let regionBorder = NSColor.white.withAlphaComponent(0.30)

    /// Layout region border on hover (GNOME `BUTTON_BORDER_COLOR_HOVER`,
    /// rgba(255,255,255,0.6)).
    static let regionBorderHovered = NSColor.white.withAlphaComponent(0.60)

    /// Layout region border under keyboard focus. No GNOME counterpart:
    /// GNOME renders focus with the hover style; the mac panel grades the
    /// border brighter so keyboard focus stays visible next to a
    /// concurrent hover (see `LayoutRegionButton`).
    static let regionBorderFocused = NSColor.white.withAlphaComponent(0.90)

    /// Layout region label text (GNOME labels render white on the dark
    /// region fill).
    static let regionLabel = NSColor.white.withAlphaComponent(0.90)

    /// The menu bar strip marking the primary display (GNOME miniature
    /// display's rgba(200,200,200,0.9) — the Ubuntu Displays convention).
    static let menuBarStrip = NSColor(white: 0.8, alpha: 0.9)

    /// The display number badge's text (GNOME monitor label,
    /// rgba(255,255,255,0.9)).
    static let displayNumber = NSColor.white.withAlphaComponent(0.90)

    /// The display number badge's fill (GNOME monitor label,
    /// rgba(0,0,0,0.6)).
    static let displayNumberBackground = NSColor.black.withAlphaComponent(0.60)

    /// Opacity for displays that are not connected right now, mirroring
    /// `INACTIVE_OPACITY` (100/255) in the GNOME miniature display.
    static let disconnectedAlpha: CGFloat = 0.4
}

/// Panel dimensions that are purely visual (radii, borders, fonts, badge
/// geometry). Everything here maps to the GNOME inline styles; the values
/// keyboard navigation depends on live in
/// `SuttoDomain.MiniaturePanelModel.Metrics` instead.
enum PanelMetrics {
    /// The panel background's corner radius. GNOME uses a squarer panel;
    /// 12 is the macOS HUD convention (deliberate deviation).
    static let panelCornerRadius: CGFloat = 12

    /// A space miniature's corner radius (GNOME `miniature-space.ts`,
    /// border-radius 6).
    static let spaceCornerRadius: CGFloat = 6

    /// A display miniature's corner radius (GNOME `miniature-display.ts`,
    /// border-radius 4).
    static let displayCornerRadius: CGFloat = 4

    /// A layout region's corner radius (GNOME `layout-button.ts`,
    /// border-radius 2).
    static let regionCornerRadius: CGFloat = 2

    /// A layout region's border width (GNOME `BUTTON_BORDER_WIDTH`).
    static let regionBorderWidth: CGFloat = 1

    /// The focused region's border width (mac-only; see
    /// ``PanelPalette/regionBorderFocused``).
    static let regionFocusedBorderWidth: CGFloat = 2

    /// Region label font size. Smaller than the GNOME 11pt: mac region
    /// labels clip to the region (GNOME lets them overflow), so a smaller
    /// face fits more labels.
    static let regionLabelFontSize: CGFloat = 10

    /// The primary display's menu bar strip height (GNOME uses 4px; 3 keeps
    /// the strip subtle at the mac miniature scale).
    static let menuBarStripHeight: CGFloat = 3

    /// Display number badge: font size and weight (GNOME 11pt bold —
    /// scaled down with the label geometry below).
    static let displayBadgeFontSize: CGFloat = 9

    /// Display number badge: corner radius (GNOME border-radius 3).
    static let displayBadgeCornerRadius: CGFloat = 2

    /// Display number badge: horizontal padding added around the number
    /// (GNOME pads 6px per side at its larger font).
    static let displayBadgeHorizontalPadding: CGFloat = 6

    /// Display number badge: distance from the display's corner (GNOME
    /// positions at margin 3).
    static let displayBadgeMargin: CGFloat = 3

    /// The "No spaces available" empty-state label's font size (GNOME
    /// renders it at 14px; 13 is the mac body size).
    static let emptyLabelFontSize: CGFloat = 13
}

/// Spacing and control sizing for the settings window, on the HIG's
/// 8-point grid: 8 between related controls, 12 between rows/groups, 16
/// between columns, 20 window insets. Colors are not defined here — the
/// settings window uses only semantic system colors (`labelColor`,
/// `secondaryLabelColor`, `separatorColor`, `controlAccentColor`, …), which
/// track light/dark mode on their own.
enum SettingsMetrics {
    /// Inset between the window edge and the content, all four sides.
    static let contentInset: CGFloat = 20

    /// Vertical gap between sibling groups (hint → body, body → button).
    static let groupSpacing: CGFloat = 12

    /// Vertical gap between rows inside a group (collection list rows).
    static let rowSpacing: CGFloat = 6

    /// Horizontal gap between controls in a row (radio → delete button,
    /// label → capture field).
    static let controlSpacing: CGFloat = 8

    /// Horizontal gap between the columns of a split layout (collection
    /// list | separator | preview).
    static let columnSpacing: CGFloat = 16

    /// Wrapping width for hint/description labels.
    static let hintWidth: CGFloat = 360

    /// Minimum content width of every settings pane, so switching to a
    /// sparse tab (Shortcuts) does not collapse the window under its
    /// toolbar, and the per-tab resize stays mostly vertical.
    static let minPaneWidth: CGFloat = 440

    /// The shortcut capture field's fixed height (a standard control row).
    static let captureFieldHeight: CGFloat = 24

    /// The shortcut capture field's minimum width (room for a long combo).
    static let captureFieldMinWidth: CGFloat = 140

    /// The shortcut capture field's corner radius.
    static let captureFieldCornerRadius: CGFloat = 6
}
