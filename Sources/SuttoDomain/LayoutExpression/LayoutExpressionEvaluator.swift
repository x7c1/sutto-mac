/// Evaluates parsed layout expressions (``LayoutExpression``) to pixel
/// values, taking the container size as context.
public enum LayoutExpressionEvaluator {
    /// Evaluates an expression to a pixel value.
    ///
    /// - Parameters:
    ///   - expression: The parsed expression AST.
    ///   - containerSize: The container size in pixels (miniature display
    ///     width or height, or the screen dimension when positioning real
    ///     windows).
    ///   - screenSize: The screen size used to scale absolute pixel values
    ///     when rendering on the miniature display. Pass `nil` (the default)
    ///     to use pixel values as-is for actual window positioning.
    /// - Returns: The resolved pixel value, rounded to the nearest integer.
    ///   Ties round toward positive infinity, matching JavaScript's
    ///   `Math.round` in the GNOME implementation.
    public static func evaluate(
        _ expression: LayoutExpression,
        containerSize: Double,
        screenSize: Double? = nil
    ) -> Double {
        let result = resolve(expression, containerSize: containerSize, screenSize: screenSize)
        return (result + 0.5).rounded(.down)
    }

    /// Recursive evaluation helper resolving each node to unrounded pixels.
    private static func resolve(
        _ expression: LayoutExpression,
        containerSize: Double,
        screenSize: Double?
    ) -> Double {
        switch expression {
        case .zero:
            return 0

        case .fraction(let numerator, let denominator):
            return (containerSize * Double(numerator)) / Double(denominator)

        case .percentage(let value):
            return containerSize * value

        case .pixel(let value):
            // When screenSize is provided, we are rendering on the miniature
            // display: scale pixel values down to maintain proportions.
            // Example: 100px on a 1920px screen → 100 * (300/1920) = 15.6px
            // on a 300px miniature. Without screenSize, pixel values are used
            // as-is (actual window positioning).
            if let screenSize {
                return value * (containerSize / screenSize)
            }
            return value

        case .add(let left, let right):
            return resolve(left, containerSize: containerSize, screenSize: screenSize)
                + resolve(right, containerSize: containerSize, screenSize: screenSize)

        case .subtract(let left, let right):
            return resolve(left, containerSize: containerSize, screenSize: screenSize)
                - resolve(right, containerSize: containerSize, screenSize: screenSize)
        }
    }
}
