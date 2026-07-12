/// A parsed layout expression, as an abstract syntax tree.
///
/// Layout expressions describe window geometry relative to a container:
/// fractions (`1/3`), percentages (`50%`), absolute pixels (`100px`), the
/// literal zero (`0`), and left-associative `+`/`-` chains of those units
/// (`50% - 10px`).
///
/// This is a faithful port of the layout-expression AST from the GNOME
/// version of Sutto, so JSON layout definitions stay compatible between the
/// two apps. The GNOME version splits the AST into `LayoutUnit` and
/// `LayoutExpression`; here both levels are collapsed into a single enum,
/// which is the idiomatic Swift shape for a recursive sum type.
///
/// Use ``LayoutExpressionParser`` to build a value from its string form and
/// ``LayoutExpressionEvaluator`` to resolve it to pixels.
public indirect enum LayoutExpression: Equatable, Sendable {
    /// The literal `0`, resolving to zero pixels.
    case zero

    /// A fraction of the container size, e.g. `1/3`.
    case fraction(numerator: Int, denominator: Int)

    /// A percentage of the container size, stored in the 0–1 range
    /// (`50%` is stored as `0.5`).
    case percentage(Double)

    /// An absolute pixel value, e.g. `100px`.
    case pixel(Double)

    /// The sum of two subexpressions.
    case add(LayoutExpression, LayoutExpression)

    /// The difference of two subexpressions (left minus right).
    case subtract(LayoutExpression, LayoutExpression)
}
