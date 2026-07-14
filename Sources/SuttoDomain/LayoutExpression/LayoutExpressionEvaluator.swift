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
        roundToPixel(
            evaluateUnrounded(
                expression, containerSize: containerSize, screenSize: screenSize))
    }

    /// Evaluates an expression to an exact, unrounded pixel value.
    ///
    /// ``evaluate(_:containerSize:screenSize:)`` rounds each expression
    /// independently (the GNOME behavior, kept for placement parity), but
    /// a caller that combines two expressions into one geometric edge —
    /// position + size — must round the *combined* edge instead: rounding
    /// the terms separately lets adjacent tiles disagree about their
    /// shared edge by a pixel (`round(0.25w) + round(0.25w)` versus
    /// `round(0.5w)`), which drew visible background gaps between tiling
    /// layout regions. See `MiniaturePanelModel`'s region computation.
    public static func evaluateUnrounded(
        _ expression: LayoutExpression,
        containerSize: Double,
        screenSize: Double? = nil
    ) -> Double {
        resolve(expression, containerSize: containerSize, screenSize: screenSize)
    }

    /// The rounding convention shared by ``evaluate(_:containerSize:screenSize:)``
    /// and edge-combining callers: nearest integer with ties toward
    /// positive infinity, matching JavaScript's `Math.round` in the GNOME
    /// implementation.
    public static func roundToPixel(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
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
