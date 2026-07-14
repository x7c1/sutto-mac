import AppKit
import SuttoDomain

/// Presents a small, non-blocking window explaining that macOS's built-in
/// window-tiling gestures react at the same window-drag as Sutto's
/// edge-trigger — so both fire at once and get in each other's way — and
/// deep-links the user to the System Settings pane that turns them off.
///
/// Sutto cannot change the system settings itself, so this is guidance only.
/// The window is dismissible and never gates app usage — it opens from the
/// status-menu warning item, which appears only while a conflicting gesture is
/// on. It names the specific toggles and, so the user isn't told to turn off
/// something already off, lists only the ones currently enabled.
/// Styled after ``PermissionOnboarding``.
@MainActor
public final class EdgeTilingGuidance {
    private var window: NSWindow?

    public init() {}

    /// Presents (or re-presents) the guidance, listing the toggles that are
    /// currently enabled per `conflicts`. The content is rebuilt on every call
    /// so a mid-session toggle is reflected without a stale cached window.
    public func present(conflicts: EdgeTilingConflicts) {
        let window = self.window ?? makeWindow()
        self.window = window

        let stack = makeContent(for: conflicts)
        window.contentView = stack
        window.setContentSize(stack.fittingSize)

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    public func dismiss() {
        window?.close()
        window = nil
    }

    // MARK: - Actions

    /// Opens System Settings at Desktop & Dock, where both tiling toggles live
    /// ("Drag windows to screen edges to tile" → `EnableTilingByEdgeDrag`, and
    /// "Drag windows to menu bar to fill screen" → `EnableTopTilingByEdgeDrag`).
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

    // MARK: - Copy

    /// The user-facing label of each conflicting toggle, paired with the edges
    /// where it collides with Sutto's edge-trigger.
    private func enabledToggleLines(for conflicts: EdgeTilingConflicts) -> [String] {
        var lines: [String] = []
        if conflicts.edgeTiling {
            lines.append(
                "•  “Drag windows to screen edges to tile” "
                    + "— reacts at the left, right, and corner edges."
            )
        }
        if conflicts.menuBarFill {
            lines.append(
                "•  “Drag windows to menu bar to fill screen” "
                    + "— reacts at the top edge."
            )
        }
        return lines
    }

    private func bodyText(for conflicts: EdgeTilingConflicts) -> String {
        let toggleList = enabledToggleLines(for: conflicts).joined(separator: "\n")
        return """
            macOS has its own window-tiling gestures that react at the same \
            screen edges as Sutto’s edge-trigger. With both on, dragging a \
            window to an edge makes macOS and Sutto respond at the same time \
            and get in each other’s way.

            These macOS gestures are currently on:

            \(toggleList)

            Sutto can’t change these system settings for you, but you can turn \
            them off:

            Open System Settings › Desktop & Dock and turn off the gesture(s) \
            listed above.

            Sutto’s edge-trigger keeps working either way — turning them off \
            only removes the conflict.
            """
    }

    // MARK: - Window construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "macOS Window Tiling"
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

        return window
    }

    private func makeContent(for conflicts: EdgeTilingConflicts) -> NSStackView {
        let headline = NSTextField(labelWithString: "macOS window tiling conflicts with Sutto")
        headline.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 2)

        let body = NSTextField(wrappingLabelWithString: bodyText(for: conflicts))
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
        return stack
    }
}
