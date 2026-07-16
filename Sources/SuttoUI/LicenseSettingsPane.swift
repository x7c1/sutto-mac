import AppKit
import Foundation
import SuttoDomain
import SuttoOperations

/// The License tab of the settings window (v0.6): shows the current gate state,
/// takes a license key and activates it, opens the purchase page, and clears a
/// stored license. The macOS surface for the commercial gate — Settings stays
/// outside the gate, so this is the one place a locked user can recover
/// (design decision #11).
///
/// The pane stays thin: the wording comes from the pure
/// ``SuttoOperations/LicensePresentation`` and the transitions from
/// ``SuttoOperations/LicenseGate`` (the shared instance the app also gates on),
/// so activating here immediately reflects in the gate. Every subview that
/// shows state is built in the initializer, so ``refresh()`` works whether or
/// not the view has been loaded into the tab view yet — matching the other
/// panes.
///
/// The backend base URL is a placeholder until a later slice, so `activate`
/// reaches the client and comes back as ``SuttoOperations/ActivationOutcome/noResponse``:
/// all three outcome branches are wired here, and the real URL simply makes the
/// success/rejection branches reachable.
@MainActor
final class LicenseSettingsPane: NSViewController {
    /// Notifies the window controller that the pane's fitting size may have
    /// changed (the feedback line appears or wraps), so the window can refit —
    /// the same hook ``LayoutsSettingsPane`` uses.
    var onContentSizeChanged: (() -> Void)?

    private let license: LicenseGate

    private let statusLabel = NSTextField(labelWithString: "")
    private let keyField = NSTextField()
    private let activateButton: NSButton
    private let buyButton: NSButton
    private let clearButton: NSButton
    private let feedbackLabel = NSTextField(labelWithString: "")

    init(license: LicenseGate) {
        self.license = license
        activateButton = NSButton(title: "Activate", target: nil, action: nil)
        buyButton = NSButton(title: "Buy License…", target: nil, action: nil)
        clearButton = NSButton(title: "Clear License", target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
        title = SettingsTab.license.title

        activateButton.target = self
        activateButton.action = #selector(activate)
        // The default button, so Return activates while the key field has focus
        // (AppKit routes Return to the window's default button once the field
        // commits its edit — no text-field delegate needed).
        activateButton.keyEquivalent = "\r"
        buyButton.target = self
        buyButton.action = #selector(buyLicense)
        clearButton.target = self
        clearButton.action = #selector(clearLicense)

        keyField.placeholderString = "Enter your license key"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LicenseSettingsPane does not support NSCoder")
    }

    override func loadView() {
        statusLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.preferredMaxLayoutWidth = SettingsMetrics.hintWidth

        let keyLabel = NSTextField(labelWithString: "License key:")
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.widthAnchor.constraint(
            greaterThanOrEqualToConstant: SettingsMetrics.captureFieldMinWidth).isActive = true

        let activateRow = NSStackView(views: [keyLabel, keyField, activateButton])
        activateRow.orientation = .horizontal
        activateRow.spacing = SettingsMetrics.controlSpacing

        feedbackLabel.font = SettingsTypography.hint
        feedbackLabel.lineBreakMode = .byWordWrapping
        feedbackLabel.maximumNumberOfLines = 0
        feedbackLabel.preferredMaxLayoutWidth = SettingsMetrics.hintWidth
        feedbackLabel.isHidden = true

        let hint = NSTextField(
            wrappingLabelWithString:
                "Buy a license to unlock Sutto after the trial, or activate a key "
                + "you already have. Clearing removes the license from this Mac."
        )
        hint.textColor = .secondaryLabelColor
        hint.font = SettingsTypography.hint
        hint.preferredMaxLayoutWidth = SettingsMetrics.hintWidth

        let actionRow = NSStackView(views: [buyButton, clearButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = SettingsMetrics.controlSpacing

        let stack = NSStackView(views: [statusLabel, activateRow, feedbackLabel, hint, actionRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsMetrics.groupSpacing
        // The window margins live on the container (required constraints, all
        // four edges), not on stack edge insets — see
        // ``SettingsPane/containerView(wrapping:)``.
        view = SettingsPane.containerView(wrapping: stack)

        refresh()
    }

    /// Re-renders everything that shows state: the status line and the Clear
    /// button's availability. Reads the shared gate, so an activation done here
    /// (or a state change elsewhere) is reflected. Does not clear the feedback
    /// line — it is the result of the user's own last action on this pane.
    func refresh() {
        let state = license.state()
        statusLabel.stringValue = LicensePresentation.statusText(for: state, now: Date())
        // Clearing only makes sense when a license is actually stored.
        clearButton.isEnabled = state.record != nil
    }

    // MARK: - Actions

    @objc private func activate() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            showFeedback(LicenseActivationFeedback(
                isSuccess: false, message: "Enter a license key to activate."))
            return
        }

        // Activation is async; disable the controls while it is in flight so a
        // second press cannot race it, and re-enable on completion. The Task
        // inherits this @MainActor, so the UI updates need no hop.
        activateButton.isEnabled = false
        keyField.isEnabled = false
        Task {
            let outcome = await license.activate(key: key)
            let feedback = LicensePresentation.activationFeedback(for: outcome)
            if feedback.isSuccess {
                keyField.stringValue = ""
            }
            showFeedback(feedback)
            activateButton.isEnabled = true
            keyField.isEnabled = true
            refresh()
        }
    }

    @objc private func buyLicense() {
        LicensePurchaseLink.open()
    }

    @objc private func clearLicense() {
        // Clearing drops a paid entitlement locally; confirm first (the same
        // caution the Layouts tab applies to deleting a collection).
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear the license from this Mac?"
        alert.informativeText =
            "Sutto returns to its trial state on this Mac. You can activate the "
            + "key again later. This does not cancel your subscription."
        let clear = alert.addButton(withTitle: "Clear")
        clear.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        license.clearLicense()
        feedbackLabel.isHidden = true
        refresh()
        onContentSizeChanged?()
    }

    private func showFeedback(_ feedback: LicenseActivationFeedback) {
        feedbackLabel.stringValue = feedback.message
        feedbackLabel.textColor = feedback.isSuccess ? .secondaryLabelColor : .systemRed
        feedbackLabel.isHidden = false
        // The line may have appeared or grown to two lines; let the window refit.
        onContentSizeChanged?()
    }
}
