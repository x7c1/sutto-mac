import AppKit
import SuttoDomain
import SuttoOperations

/// The General tab of the settings window: the "Launch Sutto at login"
/// checkbox, plus a hint and a button to System Settings while the login
/// item awaits the user's approval there.
///
/// The checkbox state and hint come from ``SuttoDomain/LaunchAtLoginStatus``,
/// read fresh from the OS through ``SuttoOperations/LaunchAtLoginUseCase`` on
/// every ``refresh()`` — no preference of our own is stored, so the pane
/// reflects changes the user made in System Settings.
///
/// Every subview that shows state is built in the initializer, so
/// ``refresh()`` works whether or not the view has been loaded into the
/// tab view yet.
@MainActor
final class GeneralSettingsPane: NSViewController {
    /// Called after a toggle or a status re-read on reactivation may have
    /// changed whether the approval hint is shown, so the window can refit
    /// to the pane's new height.
    var onContentSizeChanged: (() -> Void)?

    private let launchAtLogin: LaunchAtLoginUseCase

    private let launchAtLoginCheckbox: NSButton
    private let approvalHint: NSTextField
    private let openLoginItemsButton: NSButton

    init(launchAtLogin: LaunchAtLoginUseCase) {
        self.launchAtLogin = launchAtLogin
        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "Launch Sutto at login", target: nil, action: nil)
        approvalHint = NSTextField(wrappingLabelWithString: "")
        openLoginItemsButton = NSButton(
            title: "Open Login Items Settings…", target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
        title = SettingsTab.general.title

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        approvalHint.textColor = .secondaryLabelColor
        approvalHint.font = SettingsTypography.hint
        approvalHint.preferredMaxLayoutWidth = SettingsMetrics.hintWidth
        openLoginItemsButton.target = self
        openLoginItemsButton.action = #selector(openLoginItemsSettings)

        // The user approves (or removes) the item in System Settings, then
        // comes back to this window, which reactivates Sutto. Re-read the
        // status then, so the hint and checkbox do not stay stale until the
        // window is reopened.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GeneralSettingsPane does not support NSCoder")
    }

    override func loadView() {
        let stack = NSStackView(views: [
            launchAtLoginCheckbox, approvalHint, openLoginItemsButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsMetrics.controlSpacing
        // Hidden views (the approval hint and button) drop out of the layout.
        stack.detachesHiddenViews = true
        // The window margins live on the container — see
        // ``SettingsPane/containerView(wrapping:)``.
        view = SettingsPane.containerView(wrapping: stack)
    }

    /// Re-renders the checkbox and the approval hint from the OS status.
    func refresh() {
        let status = launchAtLogin.currentStatus()
        launchAtLoginCheckbox.state = status.isEnabled ? .on : .off
        approvalHint.stringValue = status.hint ?? ""
        approvalHint.isHidden = status.hint == nil
        openLoginItemsButton.isHidden = !status.needsApproval
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        let enable = launchAtLoginCheckbox.state == .on
        var failed = false
        do {
            try launchAtLogin.setEnabled(enable)
        } catch {
            failed = true
        }
        // Revert to (or confirm) the real status either way — before any
        // alert, so the pane behind it already shows where things stand.
        refresh()
        onContentSizeChanged?()
        if failed {
            presentFailure(enabling: enable, now: launchAtLogin.currentStatus())
        }
    }

    @objc private func openLoginItemsSettings() {
        launchAtLogin.openLoginItemsSettings()
    }

    @objc private func applicationDidBecomeActive() {
        guard viewIfLoaded?.window?.isVisible == true else { return }
        refresh()
        onContentSizeChanged?()
    }

    /// Explains a failed toggle. `status` is the one re-read after the
    /// failure: a refused registration can still leave the item registered
    /// but awaiting approval, and the alert must not then claim nothing
    /// changed while the checkbox behind it shows on.
    private func presentFailure(enabling: Bool, now status: LaunchAtLoginStatus) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if enabling {
            alert.messageText = "Could Not Turn On Launch at Login"
            alert.informativeText =
                status.needsApproval
                ? "macOS is blocking Sutto from launching at login. "
                    + "Allow it under System Settings › General › Login Items & Extensions."
                : "Sutto could not be added as a login item, so it will not launch at login."
        } else {
            alert.messageText = "Could Not Turn Off Launch at Login"
            alert.informativeText =
                "Sutto could not be removed from the login items. "
                + "You can remove it under "
                + "System Settings › General › Login Items & Extensions."
        }
        alert.runModal()
    }
}
