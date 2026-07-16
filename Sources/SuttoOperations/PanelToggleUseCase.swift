/// Toggles the layout panel: shows it when hidden, hides it when visible.
///
/// This mirrors the GNOME version, where the show shortcut doubles as a
/// toggle. Both the global shortcut and the status menu item route through
/// this use case, so they stay consistent. The panel is reached through
/// injected closures (wired by the composition root) so the decision stays
/// testable without AppKit.
///
/// **Licensing gate.** This is one of the two panel-show seams the licensing
/// gate guards (the other is ``EdgeTriggerUseCase``); the GNOME analogue is
/// the `onShowPanelShortcut` return guard. The gate is checked *only on the
/// branch that would show the panel* — `hidePanel` is never gated, so a
/// panel that is already up can always be closed even while the gate is shut.
/// When the gate is closed the panel is not shown and ``onGateClosed`` is
/// invoked instead (the composition root routes it to the licensing entry
/// point). Keeping the check here — rather than in the UI's panel — is the
/// design's rule that Operations decides and the UI merely obeys.
@MainActor
public final class PanelToggleUseCase {
    private let isPanelVisible: () -> Bool
    private let showPanel: () -> Void
    private let hidePanel: () -> Void
    private let isGateOpen: () -> Bool
    private let onGateClosed: () -> Void

    /// - Parameters:
    ///   - isPanelVisible: whether the panel is currently on screen.
    ///   - showPanel: shows the panel (only called when the gate is open).
    ///   - hidePanel: hides the panel (never gated).
    ///   - isGateOpen: whether the licensing gate permits showing the panel.
    ///     Reads the cached verdict only (``LicenseGate/isOpen()``); it must
    ///     not touch the network.
    ///   - onGateClosed: called instead of `showPanel` when a show is blocked
    ///     by a closed gate — the composition root points it at the licensing
    ///     entry point (Settings) so the user can activate or purchase.
    public init(
        isPanelVisible: @escaping () -> Bool,
        showPanel: @escaping () -> Void,
        hidePanel: @escaping () -> Void,
        isGateOpen: @escaping () -> Bool,
        onGateClosed: @escaping () -> Void
    ) {
        self.isPanelVisible = isPanelVisible
        self.showPanel = showPanel
        self.hidePanel = hidePanel
        self.isGateOpen = isGateOpen
        self.onGateClosed = onGateClosed
    }

    /// Shows the panel if it is hidden, hides it if it is visible.
    ///
    /// The show is subject to the licensing gate; the hide is not.
    public func toggle() {
        if isPanelVisible() {
            hidePanel()
        } else if isGateOpen() {
            showPanel()
        } else {
            onGateClosed()
        }
    }
}
