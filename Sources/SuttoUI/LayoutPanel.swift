import AppKit
import SuttoDomain
import SuttoOperations

/// The layout panel: a borderless, non-activating overlay showing the
/// active collection's layouts as a flat grid of buttons — one row per
/// layout group, one button per layout.
///
/// The window is an `NSPanel` with `.nonactivatingPanel` so that showing it
/// does not activate Sutto: the frontmost app stays active, which matters
/// because window placement snaps *that* app's window. The panel still
/// becomes the key window (without activating us) so it can receive Escape.
///
/// The groups are re-resolved through ``SuttoOperations/ActiveLayoutGroupsUseCase``
/// on every ``show()``, so a fresh import is reflected the next time the
/// panel opens — the GNOME panel reloads the active collection on show the
/// same way.
///
/// Deliberately minimal for v0.2. Miniature space previews, keyboard
/// navigation, and auto-hide arrive with the full panel in v0.3.
@MainActor
public final class LayoutPanel {
    /// Called when the user presses the open-settings shortcut
    /// (``SuttoDomain/KeyCombo/openSettings``, ⌘,) while the panel is
    /// visible; the panel hides itself first. Mirrors the GNOME panel,
    /// where a configurable shortcut (default Ctrl+,) opens preferences
    /// from the open panel — ⌘, being the macOS settings convention is a
    /// deliberate deviation.
    public var onOpenSettings: (() -> Void)?

    private let groups: ActiveLayoutGroupsUseCase
    private let selection: LayoutSelectionUseCase
    private var panel: OverlayPanel?
    private var renderedGrid: LayoutPanelGrid?

    public init(groups: ActiveLayoutGroupsUseCase, selection: LayoutSelectionUseCase) {
        self.groups = groups
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

    // MARK: - Actions

    @objc private func layoutButtonClicked(_ sender: NSButton) {
        guard let button = sender as? LayoutButton else { return }
        selection.select(button.layout)
        hide()
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

    /// Rebuilds the button grid from the currently active layout groups,
    /// skipping the rebuild when they match what is already rendered (the
    /// common case of reopening the panel with nothing imported meanwhile).
    private func renderContentIfNeeded(in panel: OverlayPanel) {
        let grid = LayoutPanelGrid(groups: groups.activeLayoutGroups())
        guard grid != renderedGrid else { return }
        renderedGrid = grid

        let stack = makeButtonGrid(from: grid)
        let background = makeBackground(containing: stack)
        panel.contentView = background
        panel.setContentSize(stack.fittingSize)
    }

    private func makeButtonGrid(from grid: LayoutPanelGrid) -> NSStackView {
        let rowViews = grid.rows.map { row -> NSView in
            let buttons = row.layouts.map { layout in
                LayoutButton(
                    layout: layout,
                    target: self,
                    action: #selector(layoutButtonClicked(_:))
                )
            }
            let rowStack = NSStackView(views: buttons)
            rowStack.orientation = .horizontal
            rowStack.spacing = 8
            return rowStack
        }

        let stack = NSStackView(views: rowViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return stack
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

/// A layout button that remembers which layout it stands for, so the click
/// handler does not need to reverse-map from view identity to model.
private final class LayoutButton: NSButton {
    let layout: Layout

    init(layout: Layout, target: AnyObject, action: Selector) {
        self.layout = layout
        super.init(frame: .zero)
        title = layout.label
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        self.target = target
        self.action = action
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LayoutButton does not support NSCoder")
    }
}
