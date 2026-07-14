import SuttoDomain

/// The panel surface ``EdgeTriggerUseCase`` drives, as required by the
/// operations layer and implemented by the UI layer's `LayoutPanel`.
///
/// This is deliberately a *subset* of the panel's real API: the edge-trigger
/// session only ever needs to show the panel at the cursor and follow the
/// cursor while the drag continues. Dismissal is left entirely to the panel's
/// own auto-hide and click-outside behaviour, so no suppression hook is
/// declared here. Declaring just those two operations keeps SuttoOperations
/// free of any dependency on SuttoUI/AppKit — the use case stays
/// unit-testable against a spy that records the calls, and `LayoutPanel`
/// conforms to this protocol in the composition layer.
///
/// Points are in AppKit global coordinates (bottom-left origin, y up) — the
/// same space ``DragObserving`` reports the pointer in and
/// ``SuttoDomain/EdgeTriggerPolicy`` reasons about.
///
/// Isolated to the main actor because the panel it fronts is main-thread UI.
@MainActor
public protocol EdgeTriggerPanel {
    /// Shows the panel centered on `point` (clamped into that point's work
    /// area).
    func show(at point: PixelPoint)

    /// Moves the already-visible panel to follow `point` (the cursor-follow
    /// step during a drag).
    func move(to point: PixelPoint)
}
