/// A concrete pixel rectangle produced by resolving a ``Layout`` against a
/// container size.
///
/// Coordinates are relative to the container origin; callers positioning
/// real windows add the container (work area) origin themselves, exactly as
/// the GNOME version does in `composition/window/layout-applicator.ts`.
public struct LayoutFrame: Equatable, Sendable {
    /// Horizontal offset from the container origin, in pixels.
    public let x: Double

    /// Vertical offset from the container origin, in pixels.
    public let y: Double

    /// Width in pixels.
    public let width: Double

    /// Height in pixels.
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Resolves a ``Layout``'s expression strings to a concrete ``LayoutFrame``
/// for a given container size (the monitor's usable area).
///
/// This mirrors how the GNOME version applies layouts in
/// `composition/window/layout-applicator.ts`: horizontal expressions
/// (`position.x`, `size.width`) are evaluated against the container width,
/// and vertical expressions (`position.y`, `size.height`) against the
/// container height. Each component is rounded by
/// ``LayoutExpressionEvaluator`` with the same rule as JavaScript's
/// `Math.round`, so both apps compute identical frames.
public enum LayoutFrameResolver {
    /// Resolves a layout to a pixel frame relative to the container origin.
    ///
    /// - Parameters:
    ///   - layout: The layout whose expressions to resolve.
    ///   - containerWidth: The container width in pixels.
    ///   - containerHeight: The container height in pixels.
    /// - Returns: The resolved frame, each component rounded to the nearest
    ///   integer (ties toward positive infinity).
    /// - Throws: ``LayoutExpressionParseError`` if any of the layout's
    ///   expressions is invalid.
    public static func resolve(
        _ layout: Layout,
        containerWidth: Double,
        containerHeight: Double
    ) throws(LayoutExpressionParseError) -> LayoutFrame {
        LayoutFrame(
            x: try evaluate(layout.position.x, containerSize: containerWidth),
            y: try evaluate(layout.position.y, containerSize: containerHeight),
            width: try evaluate(layout.size.width, containerSize: containerWidth),
            height: try evaluate(layout.size.height, containerSize: containerHeight)
        )
    }

    private static func evaluate(
        _ expression: String,
        containerSize: Double
    ) throws(LayoutExpressionParseError) -> Double {
        let parsed = try LayoutExpressionParser.parse(expression)
        return LayoutExpressionEvaluator.evaluate(parsed, containerSize: containerSize)
    }
}
