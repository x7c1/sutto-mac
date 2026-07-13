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
///   The panel should feel like Sutto on any platform, so these are the
///   GNOME constants themselves, not system colors — and the panel window
///   forces the dark appearance, so it looks identical regardless of the
///   system's light/dark setting, exactly like the invariably dark GNOME
///   panel. Product identity wins on this surface.
/// - ``SettingsMetrics`` carries the *settings window's* rhythm, which
///   follows the macOS HIG instead: system semantic colors only (defined
///   at the point of use, since AppKit provides them), an 8-point spacing
///   grid, standard control sizing — and the system appearance, adapting
///   to light and dark mode. OS nativeness wins on this surface.
///
/// Geometry that the domain shares with keyboard navigation (miniature
/// sizes, space/row spacing, content insets) is *not* here — it lives in
/// `SuttoDomain.MiniaturePanelModel.Metrics`, because the navigator must
/// traverse exactly the geometry the panel draws. This file only holds
/// values that are free to change without touching behavior.

/// Fixed colors for the layout panel and its miniatures: the GNOME
/// panel's palette (`ui/constants.ts`), constant for constant. The panel
/// window forces the dark appearance, so nothing here reacts to the
/// system appearance — the panel is invariably dark, like the GNOME one.
///
/// The background is a plain layer color, not a vibrancy material:
/// GNOME's `PANEL_BG_COLOR` is a 90%-opaque flat dark with no backdrop
/// blur (GNOME Shell does not blur), and a flat slightly-translucent
/// layer reproduces that exactly, where a blurred material would read as
/// a different (macOS HUD) identity.
enum PanelPalette {
    /// The panel's background (GNOME `PANEL_BG_COLOR`,
    /// rgba(40,40,40,0.9)): flat dark, slightly translucent — whatever is
    /// behind shows through faintly, unblurred, as in GNOME.
    static let panelBackground = NSColor(
        srgbRed: 40 / 255, green: 40 / 255, blue: 40 / 255, alpha: 0.9)

    /// The panel's hairline border (GNOME `PANEL_BORDER_COLOR`,
    /// rgba(255,255,255,0.2)), rimming the background so it does not melt
    /// into dark wallpapers.
    static let panelBorder = NSColor.white.withAlphaComponent(0.2)

    /// A space miniature's fill (GNOME `MINIATURE_SPACE_BG_COLOR`,
    /// rgba(80,80,80,0.9)): a raised gray over the panel background.
    static let spaceBackground = NSColor(
        srgbRed: 80 / 255, green: 80 / 255, blue: 80 / 255, alpha: 0.9)

    /// A display miniature's fill (GNOME `DISPLAY_BG_COLOR`,
    /// rgba(20,20,20,0.9)): near-black, clearly darker than the space it
    /// sits on.
    static let displayBackground = NSColor(
        srgbRed: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 0.9)

    /// Layout region fill (GNOME `BUTTON_BG_COLOR`, rgba(80,80,80,0.6)).
    static let regionBackground = NSColor(
        srgbRed: 80 / 255, green: 80 / 255, blue: 80 / 255, alpha: 0.6)

    /// Layout region fill on hover (GNOME `BUTTON_BG_COLOR_HOVER`,
    /// rgba(120,120,120,0.8)).
    static let regionBackgroundHovered = NSColor(
        srgbRed: 120 / 255, green: 120 / 255, blue: 120 / 255, alpha: 0.8)

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

    /// The menu bar strip marking the primary display (GNOME miniature
    /// display's rgba(200,200,200,0.9) — the Ubuntu Displays convention).
    static let menuBarStrip = NSColor(
        srgbRed: 200 / 255, green: 200 / 255, blue: 200 / 255, alpha: 0.9)

    /// The display number badge's text (GNOME monitor label,
    /// rgba(255,255,255,0.9)).
    static let displayNumber = NSColor.white.withAlphaComponent(0.90)

    /// The display number badge's fill (GNOME monitor label,
    /// rgba(0,0,0,0.6)).
    static let displayNumberBackground = NSColor.black.withAlphaComponent(0.60)

    /// Opacity for displays that are not connected right now, mirroring
    /// `INACTIVE_OPACITY` (100/255) in the GNOME miniature display.
    static let disconnectedAlpha: CGFloat = 0.4

    /// The footer's text and gear icon color (GNOME `FOOTER_TEXT_COLOR`,
    /// rgba(255,255,255,0.5)).
    static let footerText = NSColor.white.withAlphaComponent(0.5)

    /// The gear button's fill while hovered (GNOME's enter-event style,
    /// rgba(255,255,255,0.1)).
    static let footerButtonHoverBackground = NSColor.white.withAlphaComponent(0.1)
}

/// Panel dimensions that are purely visual (radii, borders, fonts, badge
/// geometry). Everything here maps to the GNOME inline styles; the values
/// keyboard navigation depends on live in
/// `SuttoDomain.MiniaturePanelModel.Metrics` instead.
enum PanelMetrics {
    /// The panel background's corner radius. GNOME uses a squarer panel;
    /// 12 is the macOS HUD convention (deliberate deviation).
    static let panelCornerRadius: CGFloat = 12

    /// The panel background's hairline border width (GNOME draws a 1px
    /// border around the panel).
    static let panelBorderWidth: CGFloat = 1

    /// A space miniature's corner radius (GNOME `miniature-space.ts`,
    /// border-radius 6).
    static let spaceCornerRadius: CGFloat = 6

    /// A display miniature's corner radius. Deliberate deviation from the
    /// GNOME border-radius of 4: on-screen review at real miniature size
    /// showed the rounding reading as missing/undrawn corners — the
    /// regions inside run square to the display's edge, so a rounded
    /// display clips them into notches instead of looking rounded. Square
    /// corners restore the display outline.
    static let displayCornerRadius: CGFloat = 0

    /// A layout region's corner radius. Deliberate deviation from the
    /// GNOME border-radius of 2 (user decision after on-screen review, the
    /// same call as the displays): at real miniature size even the 2pt
    /// rounding read as unwanted softness on the region frames, and square
    /// regions sit coherently inside the now-square displays.
    static let regionCornerRadius: CGFloat = 0

    /// A layout region's border width (GNOME `BUTTON_BORDER_WIDTH`).
    static let regionBorderWidth: CGFloat = 1

    /// The focused region's border width (mac-only; see
    /// ``PanelPalette/regionBorderFocused``).
    static let regionFocusedBorderWidth: CGFloat = 2

    /// The primary display's menu bar strip height (GNOME uses 4px; 3 keeps
    /// the strip subtle at the mac miniature scale).
    static let menuBarStripHeight: CGFloat = 3

    /// Display number badge: font size and weight (GNOME 11pt bold —
    /// scaled down with the label geometry below).
    static let displayBadgeFontSize: CGFloat = 9

    /// Display number badge: corner radius (GNOME border-radius 3).
    static let displayBadgeCornerRadius: CGFloat = 3

    /// Display number badge: horizontal padding added around the number
    /// (GNOME pads 6px per side at its larger font).
    static let displayBadgeHorizontalPadding: CGFloat = 6

    /// Display number badge: distance from the display's corner (GNOME
    /// positions at margin 3).
    static let displayBadgeMargin: CGFloat = 3

    /// The "No spaces available" empty-state label's font size (GNOME
    /// renders it at 14px; 13 is the mac body size).
    static let emptyLabelFontSize: CGFloat = 13

    /// Gap between the last space row and the footer (GNOME
    /// `FOOTER_MARGIN_TOP`) — tighter than the row spacing, so the footer
    /// reads as the panel's rim rather than another row.
    static let footerMarginTop: CGFloat = 3

    /// The footer label's font size (GNOME renders "Powered by Sutto" at
    /// 12px).
    static let footerLabelFontSize: CGFloat = 12

    /// The footer's fixed height (GNOME estimates its footer at ~20px:
    /// the 16px icon plus the button's vertical padding).
    static let footerHeight: CGFloat = 20

    /// The settings gear icon's point size (GNOME `SETTINGS_ICON_SIZE`).
    static let footerIconSize: CGFloat = 16

    /// The gear button's padding around the icon (GNOME
    /// `SETTINGS_PADDING_HORIZONTAL`/`_VERTICAL`, 4px and 2px).
    static let footerButtonHorizontalPadding: CGFloat = 4
    static let footerButtonVerticalPadding: CGFloat = 2

    /// The gear button's hover-fill corner radius (GNOME
    /// `SETTINGS_BORDER_RADIUS`).
    static let footerButtonCornerRadius: CGFloat = 4
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
