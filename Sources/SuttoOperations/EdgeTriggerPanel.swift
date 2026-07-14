import SuttoDomain

/// The panel surface ``EdgeTriggerUseCase`` drives, as required by the
/// operations layer and implemented by the UI layer's `LayoutPanel`.
///
/// This is deliberately a *subset* of the panel's real API: the edge-trigger
/// session shows the panel at the cursor, follows the cursor while the drag
/// continues, and hides it when the drag pulls away from the edge. The other
/// dismissal paths (auto-hide, click-outside, Escape, layout selection) stay
/// entirely with the panel's own behaviour and need no hook here. Declaring
/// just these operations keeps SuttoOperations free of any dependency on
/// SuttoUI/AppKit — the use case stays unit-testable against a spy that
/// records the calls, and `LayoutPanel` conforms to this protocol in the
/// composition layer.
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

    /// Hides the panel. Called when the drag leaves the edge band while the
    /// panel is up, so pulling away dismisses it. `LayoutPanel.hide()` fires
    /// its `onDismiss` callback, which routes back to
    /// ``EdgeTriggerUseCase/notifyPanelDismissed()``; that re-entrant path is
    /// a no-op on the policy while the drag is still live, so the drag is
    /// preserved and a re-approach re-arms.
    func hide()
}
