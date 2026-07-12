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
    /// screen containing the mouse pointer is used instead, and if the
    /// pointer is on no screen either, the primary screen.
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
    ///   - mouseLocation: The mouse pointer in AppKit coordinates, used as
    ///     the fallback when the window's center is on no screen.
    /// - Returns: The target window frame in AX coordinates, or `nil` when
    ///   `screens` is empty.
    /// - Throws: ``LayoutExpressionParseError`` if any of the layout's
    ///   expressions is invalid.
    public static func resolve(
        layout: Layout,
        windowFrame: PixelRect,
        screens: [Screen],
        mouseLocation: PixelPoint
    ) throws(LayoutExpressionParseError) -> PixelRect? {
        guard let primary = screens.first else { return nil }

        let target = targetScreen(
            windowFrame: windowFrame,
            screens: screens,
            primary: primary,
            mouseLocation: mouseLocation
        )

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
        primary: Screen,
        mouseLocation: PixelPoint
    ) -> Screen {
        let center = ScreenCoordinateConverter.appKitRect(
            fromAX: windowFrame,
            primaryScreenFrame: primary.frame
        ).center
        if let screen = screens.first(where: { $0.frame.contains(center) }) {
            return screen
        }
        if let screen = screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }
        return primary
    }
}
