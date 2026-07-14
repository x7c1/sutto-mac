/// Computes where a window should go: picks the screen the window belongs
/// to, resolves the layout against that screen's work area, and returns the
/// target frame in AX coordinates, ready to hand to the Accessibility API.
///
/// This is the macOS counterpart of the frame computation in the GNOME
/// version's `composition/window/layout-applicator.ts` (work-area origin +
/// expression resolution). The coordinate conversion has no GNOME
/// equivalent: GNOME already works in a single top-left global space, while
/// macOS splits screen geometry (AppKit, bottom-left) from window control
/// (AX, top-left).
public enum PlacementFrameResolver {
    /// Resolves the target frame for `layout` applied to a window.
    ///
    /// Screen selection: the window belongs to the screen containing the
    /// center of its frame. If the center lies on no screen (a window
    /// dragged partially off-screen can have an off-screen center), the
    /// screen *nearest* to the center is used
    /// (``Screen/containing(_:in:)``) rather than a blind primary-screen
    /// fallback, so a center on a secondary screen's outer edge stays on
    /// that secondary screen.
    ///
    /// The layout's expressions are resolved against the chosen screen's
    /// work area (``Screen/visibleFrame``). Layout offsets grow from the
    /// work area's top-left corner downward — the same orientation as AX
    /// space — so the result is the AX work-area origin plus the resolved
    /// relative frame.
    ///
    /// - Parameters:
    ///   - layout: The layout to resolve.
    ///   - windowFrame: The window's current frame in AX coordinates.
    ///   - screens: The current screens in AppKit coordinates; the first
    ///     element is the primary screen (the one whose bottom-left corner
    ///     is the AppKit origin), matching `NSScreen.screens`.
    /// - Returns: The target window frame in AX coordinates, or `nil` when
    ///   `screens` is empty.
    /// - Throws: ``LayoutExpressionParseError`` if any of the layout's
    ///   expressions is invalid.
    public static func resolve(
        layout: Layout,
        windowFrame: PixelRect,
        screens: [Screen]
    ) throws(LayoutExpressionParseError) -> PixelRect? {
        guard let primary = screens.first else { return nil }

        let target = targetScreen(
            windowFrame: windowFrame,
            screens: screens,
            primary: primary
        )
        return try resolve(layout: layout, on: target, primary: primary)
    }

    /// Resolves the target frame for `layout` applied on an explicitly
    /// chosen screen — the cross-monitor placement path: clicking a region
    /// in display *N*'s miniature places the window on screen *N*, no
    /// matter where the window currently is. The GNOME counterpart is
    /// `LayoutApplicator.applyLayout` resolving against the work area of
    /// the monitor named by the event's monitor key.
    ///
    /// - Parameters:
    ///   - layout: The layout to resolve.
    ///   - target: The screen to place on, in AppKit coordinates.
    ///   - primary: The primary screen (the first of the provider's
    ///     screens), anchoring the AppKit → AX conversion.
    /// - Returns: The target window frame in AX coordinates.
    /// - Throws: ``LayoutExpressionParseError`` if any of the layout's
    ///   expressions is invalid.
    public static func resolve(
        layout: Layout,
        on target: Screen,
        primary: Screen
    ) throws(LayoutExpressionParseError) -> PixelRect {
        let workArea = target.visibleFrame
        let relative = try LayoutFrameResolver.resolve(
            layout,
            containerWidth: workArea.width,
            containerHeight: workArea.height
        )
        let axWorkArea = ScreenCoordinateConverter.axRect(
            fromAppKit: workArea,
            primaryScreenFrame: primary.frame
        )
        return PixelRect(
            x: axWorkArea.x + relative.x,
            y: axWorkArea.y + relative.y,
            width: relative.width,
            height: relative.height
        )
    }

    private static func targetScreen(
        windowFrame: PixelRect,
        screens: [Screen],
        primary: Screen
    ) -> Screen {
        let center = ScreenCoordinateConverter.appKitRect(
            fromAX: windowFrame,
            primaryScreenFrame: primary.frame
        ).center
        // `screens` is non-empty here (the caller guards it), so the helper
        // never returns nil; `?? primary` only satisfies the type.
        return Screen.containing(center, in: screens) ?? primary
    }
}
