/// Computes where the layout panel should appear: centered on an anchor
/// point (the frontmost window's center), pushed back inside the anchor
/// screen's work area when the window sits near an edge.
///
/// This is the macOS counterpart of the GNOME version's shortcut-path
/// positioning: `showAtWindowCenter` anchors the panel on the focused
/// window's frame center and `adjustMainPanelPosition`
/// (`domain/positioning/boundary-adjuster.ts`) clamps the centered rect
/// into the work area of the monitor containing the anchor, inset by
/// `PANEL_EDGE_PADDING`. The semantics are ported exactly:
///
/// - The panel is centered on the anchor in both axes (the shortcut path
///   passes `centerVertically: true`).
/// - The clamping bounds are the work area of the screen whose *full
///   frame* contains the anchor (GNOME's `getMonitorAtPosition` tests
///   monitor geometry, then clamps within its `workArea`), inset by
///   ``edgePadding`` on every side.
/// - When the panel does not fit the padded work area, its left and top
///   edges win — GNOME clamps the max bound before the min bound in its
///   top-left-origin space, so the panel's top-left corner always stays
///   visible at the padding inset.
///
/// One deviation: when the anchor lies on no screen (GNOME falls back to
/// clamping against the whole virtual screen), the screen containing the
/// mouse pointer is used, then the primary — the same fallback chain as
/// ``PlacementFrameResolver``, which is better defined for macOS
/// arrangements with negative coordinates than a virtual-screen union.
///
/// Everything is in AppKit coordinates (global bottom-left origin, y
/// growing upward): the caller converts the AX window frame before taking
/// its center, and the result feeds `setFrameOrigin` directly.
public enum PanelPositionResolver {
    /// Minimum distance kept between the panel and the work area's edges
    /// (GNOME `PANEL_EDGE_PADDING`).
    public static let edgePadding: Double = 10

    /// Resolves the panel's frame for the given anchor.
    ///
    /// - Parameters:
    ///   - anchor: The point to center the panel on (the frontmost
    ///     window's center), in AppKit coordinates.
    ///   - panelWidth: The panel's width in points.
    ///   - panelHeight: The panel's height in points.
    ///   - screens: The current screens in AppKit coordinates; the first
    ///     element is the primary screen, matching `NSScreen.screens`.
    ///   - mouseLocation: The mouse pointer in AppKit coordinates, used as
    ///     the fallback when the anchor is on no screen.
    /// - Returns: The panel's frame in AppKit coordinates, or `nil` when
    ///   `screens` is empty.
    public static func resolve(
        anchor: PixelPoint,
        panelWidth: Double,
        panelHeight: Double,
        screens: [Screen],
        mouseLocation: PixelPoint
    ) -> PixelRect? {
        guard let primary = screens.first else { return nil }

        let screen =
            screens.first { $0.frame.contains(anchor) }
            ?? screens.first { $0.frame.contains(mouseLocation) }
            ?? primary
        let workArea = screen.visibleFrame

        // Center on the anchor, then clamp into the padded work area.
        //
        // The clamp orders are asymmetric on purpose, porting GNOME's
        // top-left-origin behavior into this bottom-up space: when the
        // panel is larger than the padded work area, the *left* edge wins
        // horizontally (`max` applied last) and the *top* edge wins
        // vertically (`min` applied last, `maxYOrigin` being the origin
        // that puts the panel's top edge at the padding inset).
        let minX = workArea.x + edgePadding
        let maxXOrigin = workArea.maxX - edgePadding - panelWidth
        let x = max(min(anchor.x - panelWidth / 2, maxXOrigin), minX)

        let minY = workArea.y + edgePadding
        let maxYOrigin = workArea.maxY - edgePadding - panelHeight
        let y = min(max(anchor.y - panelHeight / 2, minY), maxYOrigin)

        return PixelRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }
}
