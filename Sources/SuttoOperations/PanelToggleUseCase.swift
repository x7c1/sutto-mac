/// Toggles the layout panel: shows it when hidden, hides it when visible.
///
/// This mirrors the GNOME version, where the show shortcut doubles as a
/// toggle. Both the global shortcut and the status menu item route through
/// this use case, so they stay consistent. The panel is reached through
/// injected closures (wired by the composition root) so the decision stays
/// testable without AppKit.
@MainActor
public final class PanelToggleUseCase {
    private let isPanelVisible: () -> Bool
    private let showPanel: () -> Void
    private let hidePanel: () -> Void

    public init(
        isPanelVisible: @escaping () -> Bool,
        showPanel: @escaping () -> Void,
        hidePanel: @escaping () -> Void
    ) {
        self.isPanelVisible = isPanelVisible
        self.showPanel = showPanel
        self.hidePanel = hidePanel
    }

    /// Shows the panel if it is hidden, hides it if it is visible.
    public func toggle() {
        if isPanelVisible() {
            hidePanel()
        } else {
            showPanel()
        }
    }
}
