/// Converts rectangles between the two global coordinate spaces used on
/// macOS.
///
/// - **AppKit space** (`NSScreen.frame`, `NSEvent.mouseLocation`): origin at
///   the *bottom-left* corner of the primary screen, y grows *upward*.
/// - **AX space** (`kAXPositionAttribute` of the Accessibility API, and also
///   `CGWindow`/`CGDisplay` APIs): origin at the *top-left* corner of the
///   primary screen, y grows *downward*.
///
/// Both spaces share the x axis and the primary screen's top edge as the
/// mirror line, so converting flips y around that edge and leaves everything
/// else untouched. With `primaryFrame` being the primary screen's frame in
/// AppKit space (its origin is `(0, 0)` by definition, so `primaryFrame.maxY`
/// is the primary screen's height):
///
/// ```
/// axRect.y     = primaryFrame.maxY - appKitRect.maxY
/// appKitRect.y = primaryFrame.maxY - axRect.maxY
/// ```
///
/// A rectangle's stored origin is its bottom-left corner in AppKit space and
/// its top-left corner in AX space — the same physical rectangle keeps its
/// `x`, `width`, and `height`, and only `y` moves. The two formulas above are
/// the same function, so the conversion is an involution: applying it twice
/// returns the original rectangle exactly (no floating-point drift, since it
/// is one subtraction each way).
///
/// This holds for any multi-monitor arrangement, including screens with
/// negative coordinates (left of or below the primary) and vertically
/// stacked screens, because both spaces are global: secondary screens only
/// shift rectangle origins, never the mirror line.
public enum ScreenCoordinateConverter {
    /// Converts a rectangle from AppKit space to AX space.
    ///
    /// - Parameters:
    ///   - rect: A rectangle in AppKit (bottom-left) coordinates.
    ///   - primaryScreenFrame: The primary screen's frame in AppKit
    ///     coordinates (`Screen.frame` of the first screen).
    public static func axRect(
        fromAppKit rect: PixelRect,
        primaryScreenFrame: PixelRect
    ) -> PixelRect {
        PixelRect(
            x: rect.x,
            y: primaryScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Converts a rectangle from AX space to AppKit space.
    ///
    /// - Parameters:
    ///   - rect: A rectangle in AX (top-left) coordinates.
    ///   - primaryScreenFrame: The primary screen's frame in AppKit
    ///     coordinates (`Screen.frame` of the first screen).
    public static func appKitRect(
        fromAX rect: PixelRect,
        primaryScreenFrame: PixelRect
    ) -> PixelRect {
        PixelRect(
            x: rect.x,
            y: primaryScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
