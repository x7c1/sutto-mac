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
/// The panel is fully keyboard-operable while it is key: arrows (and the
/// other bindings of ``SuttoDomain/PanelKeyBinding``) move a focus
/// highlight across the layout regions along the traversal rules of
/// ``SuttoDomain/MiniaturePanelNavigator``, and Return applies the focused
/// region through the same selection path a click takes — display
/// targeting included. The panel opens unfocused (the GNOME navigator
/// starts on the *selected* layout, and selection state is deferred within
/// v0.3), so the first arrow press focuses the top-left region.
///
/// Auto-hide and space toggling arrive later within v0.3.
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

    /// Keyboard-navigation state, rebuilt whenever the content is: the
    /// traversal rules, the region buttons by coordinate (for the focus
    /// highlight), and the focused coordinate — `nil` until the first key
    /// press, and reset on every hide the way the GNOME navigator's
    /// `disable()` drops its focus.
    private var navigator: MiniaturePanelNavigator?
    private var regionButtons: [MiniaturePanelNavigator.Coordinate: LayoutRegionButton] = [:]
    private var focusedCoordinate: MiniaturePanelNavigator.Coordinate?

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

    /// Hides the panel. Keyboard focus returns to wherever it was, and the
    /// panel's own navigation focus is dropped so the next show starts
    /// unfocused again.
    public func hide() {
        clearFocus()
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
        panel.onPanelKey = { [weak self] action in
            self?.handle(action)
        }
        return panel
    }

    // MARK: - Keyboard navigation

    private func handle(_ action: PanelKeyAction) {
        switch action {
        case .move(let direction):
            // No candidate in that direction: keep the current focus (no
            // wrap-around, like the GNOME navigator).
            if let next = navigator?.move(from: focusedCoordinate, direction: direction) {
                focus(next)
            }
        case .cycle(let reverse):
            if let next = navigator?.advance(from: focusedCoordinate, reverse: reverse) {
                focus(next)
            }
        case .activate:
            // Return with nothing focused is a no-op, like the GNOME
            // navigator's selectCurrentButton.
            guard
                let focusedCoordinate,
                let event = navigator?.selection(at: focusedCoordinate)
            else { return }
            // The exact click path: same selection use case, same hide.
            selection.select(event)
            hide()
        }
    }

    private func focus(_ coordinate: MiniaturePanelNavigator.Coordinate) {
        if let focusedCoordinate {
            regionButtons[focusedCoordinate]?.isKeyboardFocused = false
        }
        focusedCoordinate = coordinate
        regionButtons[coordinate]?.isKeyboardFocused = true
    }

    private func clearFocus() {
        if let focusedCoordinate {
            regionButtons[focusedCoordinate]?.isKeyboardFocused = false
        }
        focusedCoordinate = nil
    }

    /// Rebuilds the miniature previews from the current panel model,
    /// skipping the rebuild when it matches what is already rendered (the
    /// common case of reopening the panel with nothing changed meanwhile).
    /// A rebuild also rebuilds the keyboard navigator, whose traversal
    /// geometry must match the rendered content.
    private func renderContentIfNeeded(in panel: OverlayPanel) {
        let model = self.model.panelModel()
        guard model != renderedModel else { return }
        renderedModel = model

        clearFocus()
        let content = makeContent(from: model)
        navigator = MiniaturePanelNavigator(model: model)
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
        regionButtons = [:]
        let rowViews = model.rows.enumerated().map { rowIndex, row -> NSView in
            let miniatures = row.spaces.enumerated().map { spaceIndexInRow, space -> NSView in
                let view = MiniatureSpaceView(
                    space: space,
                    index: spaceIndex,
                    onRegionClicked: onRegionClicked
                )
                spaceIndex += 1
                registerRegionButtons(of: view, row: rowIndex, space: spaceIndexInRow)
                return view
            }
            let rowStack = NSStackView(views: miniatures)
            rowStack.orientation = .horizontal
            rowStack.alignment = .top
            rowStack.spacing = MiniaturePanelModel.Metrics.spaceSpacing
            return rowStack
        }

        let stack = NSStackView(views: rowViews.isEmpty ? [makeEmptyLabel()] : rowViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = MiniaturePanelModel.Metrics.rowSpacing
        let inset = MiniaturePanelModel.Metrics.contentInset
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        return stack
    }

    /// Indexes a space miniature's region buttons by navigator coordinate,
    /// so key presses can restyle the focused button. The nesting mirrors
    /// the model exactly (the views are built from it in order), which is
    /// what makes the indices line up.
    private func registerRegionButtons(of view: MiniatureSpaceView, row: Int, space: Int) {
        for (displayIndex, displayView) in view.displayViews.enumerated() {
            for (regionIndex, button) in displayView.regionButtons.enumerated() {
                let coordinate = MiniaturePanelNavigator.Coordinate(
                    row: row, space: space, display: displayIndex, region: regionIndex)
                regionButtons[coordinate] = button
            }
        }
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
/// default), reports Escape via `onCancel`, the open-settings shortcut via
/// `onOpenSettings`, and navigation key presses via `onPanelKey`.
private final class OverlayPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onPanelKey: ((PanelKeyAction) -> Void)?

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
    ///
    /// Navigation keys (``SuttoDomain/PanelKeyBinding``) are consumed here;
    /// anything the binding does not recognize keeps its existing routing
    /// (the GNOME navigator propagates unrecognized keys the same way).
    override func keyDown(with event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        if event.keyCode == escapeKeyCode {
            onCancel?()
            return
        }
        if let action = PanelKeyBinding.action(for: KeyComboTranslation.combo(from: event)),
            let onPanelKey
        {
            onPanelKey(action)
            return
        }
        super.keyDown(with: event)
    }
}
