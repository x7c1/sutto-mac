/// Computes where the layout panel should appear: anchored on a point
/// (the frontmost window's center on the shortcut path, or the cursor on
/// the edge-trigger path), pushed back inside the anchor screen's work
/// area when it sits near an edge.
///
/// This is the macOS counterpart of the GNOME version's shortcut-path
/// positioning: `showAtWindowCenter` anchors the panel on the focused
/// window's frame center and `adjustMainPanelPosition`
/// (`domain/positioning/boundary-adjuster.ts`) clamps the centered rect
/// into the work area of the monitor containing the anchor, inset by
/// `PANEL_EDGE_PADDING`. The semantics are ported exactly:
///
/// - Horizontally the panel is always centered on the anchor (the shortcut
///   path passes `centerVertically: true`).
/// - Vertically the caller chooses via ``VerticalAnchor``: the shortcut
///   path centers on the anchor; the edge-trigger path anchors the panel's
///   *top edge* at the cursor so the panel hangs below it, which reads far
///   less intrusively than covering the cursor with the panel's middle.
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
/// clamping against the whole virtual screen), the screen *nearest* to the
/// anchor is used (``Screen/containing(_:in:)``), which is better defined
/// for macOS arrangements with negative coordinates than a virtual-screen
/// union — and, unlike a blind primary-screen fallback, keeps a point on a
/// secondary screen's outer edge on that secondary screen.
///
/// Everything is in AppKit coordinates (global bottom-left origin, y
/// growing upward): the caller converts the AX window frame before taking
/// its center, and the result feeds `setFrameOrigin` directly.
public enum PanelPositionResolver {
    /// How the panel is anchored to the anchor point along the vertical
    /// axis. Horizontal anchoring is always centered.
    public enum VerticalAnchor {
        /// The panel is centered on the anchor's y — the shortcut path,
        /// which sits the panel over the captured window's center.
        case center
        /// The panel's top edge sits at the anchor's y, so the panel hangs
        /// below it — the edge-trigger path, which drops the panel below
        /// the cursor rather than covering it.
        case top
    }

    /// Minimum distance kept between the panel and the work area's edges
    /// (GNOME `PANEL_EDGE_PADDING`).
    public static let edgePadding: Double = 10

    /// Resolves the panel's frame for the given anchor.
    ///
    /// - Parameters:
    ///   - anchor: The point to anchor the panel on (the frontmost
    ///     window's center on the shortcut path, or the cursor on the
    ///     edge-trigger path), in AppKit coordinates.
    ///   - panelWidth: The panel's width in points.
    ///   - panelHeight: The panel's height in points.
    ///   - verticalAnchor: Whether to center the panel on the anchor's y
    ///     or hang it below by anchoring its top edge there. Defaults to
    ///     ``VerticalAnchor/center`` (the shortcut path).
    ///   - screens: The current screens in AppKit coordinates; the first
    ///     element is the primary screen, matching `NSScreen.screens`.
    /// - Returns: The panel's frame in AppKit coordinates, or `nil` when
    ///   `screens` is empty.
    public static func resolve(
        anchor: PixelPoint,
        panelWidth: Double,
        panelHeight: Double,
        verticalAnchor: VerticalAnchor = .center,
        screens: [Screen]
    ) -> PixelRect? {
        guard let screen = Screen.containing(anchor, in: screens) else { return nil }
        let workArea = screen.visibleFrame

        // Anchor on the point, then clamp into the padded work area.
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

        // Horizontal anchoring is always centered; only the vertical
        // origin differs. `.center` puts the anchor at the panel's middle
        // (`anchor.y - panelHeight / 2`); `.top` puts it at the panel's top
        // edge, which in this bottom-up space means the origin sits a full
        // `panelHeight` below the anchor (`anchor.y - panelHeight`).
        let unclampedY: Double
        switch verticalAnchor {
        case .center:
            unclampedY = anchor.y - panelHeight / 2
        case .top:
            unclampedY = anchor.y - panelHeight
        }
        let minY = workArea.y + edgePadding
        let maxYOrigin = workArea.maxY - edgePadding - panelHeight
        let y = min(max(unclampedY, minY), maxYOrigin)

        return PixelRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }
}
