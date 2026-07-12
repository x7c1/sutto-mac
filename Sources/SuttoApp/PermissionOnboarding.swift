import AppKit
import SuttoCore

/// Presents a small window that guides the user through granting the
/// Accessibility permission Sutto needs to move and resize windows, and
/// polls until the permission is granted.
@MainActor
final class PermissionOnboarding {
    private let permissionChecker: AccessibilityPermissionChecker
    private var window: NSWindow?
    private var pollTimer: Timer?

    init(permissionChecker: AccessibilityPermissionChecker) {
        self.permissionChecker = permissionChecker
    }

    func present() {
        let window = self.window ?? makeWindow()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)

        startPolling()
    }

    func dismiss() {
        stopPolling()
        window?.close()
        window = nil
    }

    // MARK: - Actions

    @objc private func requestPermission() {
        permissionChecker.requestPermission()
    }

    @objc private func openSystemSettings() {
        let urlString =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(pollPermission),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func pollPermission() {
        if PermissionOnboardingPolicy.isComplete(for: permissionChecker.currentStatus()) {
            dismiss()
        }
    }

    // MARK: - Window construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Sutto"
        window.isReleasedWhenClosed = false

        // Stop polling if the user closes the window manually.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopPolling()
            }
        }

        let headline = NSTextField(labelWithString: "Sutto needs Accessibility permission")
        headline.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 2)

        let body = NSTextField(
            wrappingLabelWithString: """
                Sutto moves and resizes windows of other applications. \
                macOS requires your explicit permission for that.

                Click “Request Permission”, then enable Sutto in \
                System Settings › Privacy & Security › Accessibility. \
                This window closes automatically once permission is granted.
                """
        )
        body.preferredMaxLayoutWidth = 360

        let requestButton = NSButton(
            title: "Request Permission",
            target: self,
            action: #selector(requestPermission)
        )
        requestButton.keyEquivalent = "\r"

        let settingsButton = NSButton(
            title: "Open System Settings",
            target: self,
            action: #selector(openSystemSettings)
        )

        let buttonRow = NSStackView(views: [settingsButton, requestButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [headline, body, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        return window
    }
}
