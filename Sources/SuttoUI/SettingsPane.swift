import AppKit

/// Shared construction for settings pane views.
@MainActor
enum SettingsPane {
    /// Wraps a pane's content in a plain container that enforces the
    /// settings window margin (``SettingsMetrics/contentInset``) on all
    /// four edges as *required* equal constraints, plus the shared
    /// minimum pane width.
    ///
    /// The margins are deliberately not `NSStackView.edgeInsets`: the
    /// stack binds its trailing and bottom insets through internal
    /// lower-priority constraints, and the pane's fitting size — which
    /// sizes the window — came out without the trailing inset, leaving
    /// the Layouts preview flush against the window's right edge while
    /// the left margin was fine. Required container constraints make all
    /// four margins symmetric by construction, whatever the stack's
    /// alignment and hugging do.
    static func containerView(wrapping content: NSView) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        let inset = SettingsMetrics.contentInset
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            content.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: inset),
            container.trailingAnchor.constraint(
                equalTo: content.trailingAnchor, constant: inset),
            container.bottomAnchor.constraint(
                equalTo: content.bottomAnchor, constant: inset),
            container.widthAnchor.constraint(
                greaterThanOrEqualToConstant: SettingsMetrics.minPaneWidth),
        ])
        return container
    }
}
