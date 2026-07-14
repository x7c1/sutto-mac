/// An opaque handle to a window captured as the target of a placement
/// interaction.
///
/// The operations layer only ever holds the handle; the infra layer that
/// created it (``WindowControlling``'s implementation) is the sole owner of
/// the underlying Accessibility element and the only code that unwraps it.
/// Keeping the concrete type out of this layer is what lets
/// ``WindowControlling`` deal in captured windows without leaking AX types
/// upward.
public protocol TargetWindow: AnyObject {}
