import AppKit
import SuttoDomain
import SuttoOperations

/// The layout panel: a borderless, non-activating overlay showing the
/// active collection as miniature space previews — one miniature per
/// enabled space, each rendering *all* displays in their physical
/// arrangement, with the assigned layouts drawn as clickable regions.
/// Clicking a region places the frontmost window on that region's display
/// with that layout.
///
/// The window is an `NSPanel` with `.nonactivatingPanel` so that showing it
/// does not activate Sutto: the frontmost app stays active, which matters
/// because window placement snaps *that* app's window. The panel still
/// becomes the key window (without activating us) so it can receive Escape.
///
/// The model is re-resolved through
/// ``SuttoOperations/ActivePanelModelUseCase`` on every ``show()``, so a
/// fresh import or a display change is reflected the next time the panel
/// opens — the GNOME panel reloads the active collection on show the same
/// way.
///
/// Keyboard navigation, auto-hide, and space toggling arrive later within
/// v0.3.
@MainActor
public final class LayoutPanel {
    /// Called when the user presses the open-settings shortcut
    /// (``SuttoDomain/KeyCombo/openSettings``, ⌘,) while the panel is
    /// visible; the panel hides itself first. Mirrors the GNOME panel,
    /// where a configurable shortcut (default Ctrl+,) opens preferences
    /// from the open panel — ⌘, being the macOS settings convention is a
    /// deliberate deviation.
    public var onOpenSettings: (() -> Void)?

    private let model: ActivePanelModelUseCase
    private let selection: LayoutSelectionUseCase
    private var panel: OverlayPanel?
    private var renderedModel: MiniaturePanelModel?

    public init(model: ActivePanelModelUseCase, selection: LayoutSelectionUseCase) {
        self.model = model
        self.selection = selection
    }

    /// Whether the panel is currently on screen.
    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Shows the panel centered on the screen containing the mouse pointer
    /// (falling back to the main screen), and gives it key status so Escape
    /// works. Showing does not activate the app.
    public func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        renderContentIfNeeded(in: panel)

        if let screen = screenWithMouse() {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(
                NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.midY - size.height / 2
                ))
        } else {
            panel.center()
        }

        // A non-activating panel can take key status without activating the
        // app; canBecomeKey is overridden because borderless windows refuse
        // key status by default.
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the panel. Keyboard focus returns to wherever it was.
    public func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Panel construction

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in
            self?.hide()
        }
        panel.onOpenSettings = { [weak self] in
            // The GNOME panel opens preferences and hides in the same
            // gesture; keep that pairing.
            self?.hide()
            self?.onOpenSettings?()
        }
        return panel
    }

    /// Rebuilds the miniature previews from the current panel model,
    /// skipping the rebuild when it matches what is already rendered (the
    /// common case of reopening the panel with nothing changed meanwhile).
    private func renderContentIfNeeded(in panel: OverlayPanel) {
        let model = self.model.panelModel()
        guard model != renderedModel else { return }
        renderedModel = model

        let content = makeContent(from: model)
        let background = makeBackground(containing: content)
        panel.contentView = background
        panel.setContentSize(content.fittingSize)
    }

    private func makeContent(from model: MiniaturePanelModel) -> NSStackView {
        let onRegionClicked: (LayoutSelectedEvent) -> Void = { [weak self] event in
            self?.selection.select(event)
            self?.hide()
        }

        // Space numbering is continuous across rows (reading order), so
        // the AX labels identify spaces the way a user counts them.
        var spaceIndex = 0
        let rowViews = model.rows.map { row -> NSView in
            let miniatures = row.spaces.map { space -> NSView in
                let view = MiniatureSpaceView(
                    space: space,
                    index: spaceIndex,
                    onRegionClicked: onRegionClicked
                )
                spaceIndex += 1
                return view
            }
            let rowStack = NSStackView(views: miniatures)
            rowStack.orientation = .horizontal
            rowStack.alignment = .top
            rowStack.spacing = 6
            return rowStack
        }

        let stack = NSStackView(views: rowViews.isEmpty ? [makeEmptyLabel()] : rowViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return stack
    }

    /// Shown when every space is disabled (or nothing resolves at all),
    /// matching the GNOME panel's "No spaces available" message.
    private func makeEmptyLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "No spaces available")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeBackground(containing stack: NSStackView) -> NSVisualEffectView {
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        ])
        return background
    }

    private func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
    }
}

/// A borderless panel that can become key (borderless windows cannot by
/// default), reports Escape via `onCancel`, and reports the open-settings
/// shortcut via `onOpenSettings`.
private final class OverlayPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    override var canBecomeKey: Bool { true }

    /// ⌘-modified key-downs travel the key-equivalent path rather than
    /// `keyDown`, and a borderless panel has no menu or views that would
    /// claim them; intercepting in `sendEvent` catches the open-settings
    /// combo regardless of which routing applies.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, KeyComboTranslation.combo(from: event) == .openSettings {
            onOpenSettings?()
            return
        }
        super.sendEvent(event)
    }

    /// Escape reaches the window as `cancelOperation(_:)` through the
    /// responder chain when no view handles it.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Fallback for the raw Escape key-down in case the event does not get
    /// routed through `cancelOperation(_:)` (borderless panels are not part
    /// of the standard window machinery that usually guarantees it).
    override func keyDown(with event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        if event.keyCode == escapeKeyCode {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}
