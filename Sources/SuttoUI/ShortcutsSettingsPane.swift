import AppKit
import SuttoDomain
import SuttoOperations

/// The Shortcuts tab of the settings window: capture the panel-toggle
/// combo and reset it to the default. Capture validation is
/// ``SuttoDomain/ShortcutCapturePolicy``; live re-registration is
/// ``SuttoOperations/PanelShortcutUseCase`` — the pane only renders state
/// and reports failures.
///
/// Every subview that shows state is built in the initializer, so
/// ``refresh()`` works whether or not the view has been loaded into the
/// tab view yet.
@MainActor
final class ShortcutsSettingsPane: NSViewController {
    private let shortcut: PanelShortcutUseCase

    private let captureField: ShortcutCaptureField
    private let resetButton: NSButton

    init(shortcut: PanelShortcutUseCase) {
        self.shortcut = shortcut
        captureField = ShortcutCaptureField(combo: shortcut.currentCombo())
        resetButton = NSButton(title: "Reset to Default", target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
        title = SettingsTab.shortcuts.title

        captureField.onCapture = { [weak self] combo in
            self?.shortcutCaptured(combo)
        }
        resetButton.target = self
        resetButton.action = #selector(resetShortcut)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ShortcutsSettingsPane does not support NSCoder")
    }

    override func loadView() {
        let row = NSStackView(views: [
            NSTextField(labelWithString: "Toggle panel:"), captureField, resetButton,
        ])
        row.orientation = .horizontal
        row.spacing = SettingsMetrics.controlSpacing

        let hint = NSTextField(
            wrappingLabelWithString:
                "Click the field, then press the new key combination. "
                + "Press Escape to cancel."
        )
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.preferredMaxLayoutWidth = SettingsMetrics.hintWidth

        let stack = NSStackView(views: [row, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsMetrics.controlSpacing
        let inset = SettingsMetrics.contentInset
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        stack.widthAnchor.constraint(
            greaterThanOrEqualToConstant: SettingsMetrics.minPaneWidth
        ).isActive = true
        view = stack
    }

    /// Re-renders the capture field and the Reset button from the stored
    /// shortcut, and ends a capture left dangling — clicking another
    /// control does not take first-responder status away from the field on
    /// its own.
    func refresh() {
        if let window = captureField.window, window.firstResponder === captureField {
            window.makeFirstResponder(nil)
        }
        captureField.combo = shortcut.currentCombo()
        resetButton.isEnabled = !shortcut.isDefault()
    }

    // MARK: - Actions

    @objc private func resetShortcut() {
        do {
            try shortcut.resetToDefault()
        } catch {
            presentFailure(for: .defaultTogglePanel)
        }
        refresh()
    }

    private func shortcutCaptured(_ combo: KeyCombo) {
        do {
            try shortcut.update(to: combo)
        } catch {
            presentFailure(for: combo)
        }
        refresh()
    }

    private func presentFailure(for combo: KeyCombo) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Shortcut Not Available"
        alert.informativeText =
            "\(combo.displayString) could not be registered. "
            + "Another app may already be using it; the previous shortcut stays active."
        alert.runModal()
    }
}
