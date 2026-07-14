import AppKit

/// Presents a small, non-blocking window explaining that macOS's built-in
/// edge-tiling collides with Sutto's edge-trigger, and deep-links the user to
/// the System Settings pane that turns it off.
///
/// Sutto cannot change the system setting itself, so this is guidance only.
/// The window is dismissible and never gates app usage — it opens from the
/// status-menu warning item, which appears only while OS edge-tiling is on.
/// Styled after ``PermissionOnboarding``.
@MainActor
public final class EdgeTilingGuidance {
    private var window: NSWindow?

    public init() {}

    public func present() {
        let window = self.window ?? makeWindow()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    public func dismiss() {
        window?.close()
        window = nil
    }

    // MARK: - Actions

    /// Opens System Settings at Desktop & Dock, where the "Drag windows to
    /// screen edges to tile" toggle lives (writing `EnableTilingByEdgeDrag`).
    /// Best-effort: the deep link opens the right pane on Sequoia; if the URL
    /// scheme ever changes, System Settings still opens and the on-screen
    /// steps say where to go.
    @objc private func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.Desktop-Settings.extension"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func close() {
        dismiss()
    }

    // MARK: - Window construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "macOS Edge Tiling"
        window.isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window = nil
            }
        }

        let headline = NSTextField(labelWithString: "macOS edge tiling is turned on")
        headline.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 2)

        let body = NSTextField(
            wrappingLabelWithString: """
                macOS has its own “drag a window to a screen edge to tile it” \
                feature, which fires at the same edges Sutto uses for its \
                edge-trigger. With both on, dragging to an edge can trigger \
                the macOS tiling instead of Sutto’s panel.

                Sutto can’t change this system setting for you, but you can \
                turn it off:

                Open System Settings › Desktop & Dock and turn off \
                “Drag windows to screen edges to tile”.

                Sutto’s edge-trigger keeps working either way — this only \
                removes the conflict.
                """
        )
        body.preferredMaxLayoutWidth = SettingsMetrics.hintWidth

        let settingsButton = NSButton(
            title: "Open Desktop & Dock Settings",
            target: self,
            action: #selector(openSystemSettings)
        )
        settingsButton.keyEquivalent = "\r"

        let closeButton = NSButton(
            title: "Close",
            target: self,
            action: #selector(close)
        )

        let buttonRow = NSStackView(views: [closeButton, settingsButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = SettingsMetrics.controlSpacing

        let stack = NSStackView(views: [headline, body, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsMetrics.groupSpacing
        let inset = SettingsMetrics.contentInset
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)

        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        return window
    }
}
