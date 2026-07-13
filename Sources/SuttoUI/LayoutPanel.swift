import AppKit
import SuttoDomain
import SuttoOperations

/// The layout panel: a borderless, non-activating overlay showing the
/// active collection as miniature space previews — one miniature per
/// enabled space, each rendering *all* displays in their physical
/// arrangement, with the assigned layouts drawn as clickable regions.
/// Clicking a region places the frontmost window on that region's display
/// with that layout — and the panel stays open, so the user can keep
/// adjusting; the GNOME selection handler applies the layout without
/// hiding the same way (the v0.1 hide-on-select was provisional).
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
/// The panel dismisses the way the GNOME panel does. It auto-hides after
/// the cursor has stayed outside it for
/// ``SuttoDomain/PanelAutoHidePolicy/autoHideDelay`` — the *decision*
/// logic is the pure ``SuttoDomain/PanelAutoHidePolicy``; this class only
/// feeds it enter/exit events from a whole-panel tracking area and runs
/// the one timer its effects call for. A mouse click anywhere outside the
/// panel closes it immediately, like a click on the GNOME panel's
/// full-screen background actor: a *global* `NSEvent` monitor sees clicks
/// in other apps (mouse-only global monitors need no Accessibility
/// permission), a *local* monitor covers clicks landing in Sutto's own
/// windows. A `CGEventTap` would also work but is deliberately avoided:
/// EDR software flags event taps, and the monitors are sufficient. Unlike
/// the GNOME background actor the monitors cannot swallow the outside
/// click — the click also does whatever it would normally do.
///
/// Spaces disabled in the settings window's preview are the ones the
/// show-time model resolution filters out; the toggle needs no wiring here
/// beyond that re-resolution.
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
    private let position: PanelPositionUseCase
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

    /// Auto-hide state (the pure GNOME-ported policy) and the one timer
    /// its effects schedule and cancel.
    private var autoHide = PanelAutoHidePolicy()
    private var autoHideTimer: Timer?

    /// The global + local mouse-down monitors implementing
    /// click-outside-closes, installed on show and removed on hide (a
    /// monitor that is never removed keeps firing — and leaks).
    private var mouseMonitors: [Any] = []

    public init(
        model: ActivePanelModelUseCase,
        selection: LayoutSelectionUseCase,
        position: PanelPositionUseCase
    ) {
        self.model = model
        self.selection = selection
        self.position = position
    }

    /// Whether the panel is currently on screen.
    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Shows the panel centered over the frontmost app's focused window,
    /// pushed back inside that screen's work area when the window sits
    /// near an edge — the GNOME shortcut path (`showAtWindowCenter`).
    /// Without a readable focused window (none exists, or the
    /// Accessibility permission is missing) it falls back to centering on
    /// the screen containing the mouse pointer (then the main screen).
    /// The panel gets key status so Escape works; showing does not
    /// activate the app.
    public func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        renderContentIfNeeded(in: panel)

        let size = panel.frame.size
        if let frame = position.panelFrame(width: size.width, height: size.height) {
            panel.setFrameOrigin(NSPoint(x: frame.x, y: frame.y))
        } else if let screen = screenWithMouse() {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.midY - size.height / 2
                ))
        } else {
            panel.center()
        }

        // Hover state resets on every show (GNOME show() calls
        // resetHoverStates()): the grace timer arms only when the cursor
        // actually enters and leaves, so a panel opened by shortcut with
        // the cursor elsewhere stays up for keyboard navigation.
        apply(autoHide.panelShown())
        installMouseMonitors()

        // A non-activating panel can take key status without activating the
        // app; canBecomeKey is overridden because borderless windows refuse
        // key status by default.
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the panel. Keyboard focus returns to wherever it was, and the
    /// panel's own navigation focus is dropped so the next show starts
    /// unfocused again. Any pending auto-hide is cancelled and the mouse
    /// monitors come down with the panel.
    public func hide() {
        apply(autoHide.panelHidden())
        removeMouseMonitors()
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
        // The panel is invariably dark, like the GNOME panel: the palette
        // is fixed, and forcing the appearance keeps the few semantic
        // colors (the empty-state label) resolving against dark no matter
        // the system setting. The settings window, by contrast, stays
        // system-adaptive — product identity here, OS nativeness there.
        panel.appearance = NSAppearance(named: .darkAqua)
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
            // The exact click path: same selection use case, and like the
            // click the panel stays open for further adjustments.
            selection.select(event)
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
        // Selecting a layout places the window and keeps the panel open —
        // the GNOME selection handler never hides — so the user can keep
        // trying layouts; the panel closes via Escape, an outside click, or
        // auto-hide.
        let onRegionClicked: (LayoutSelectedEvent) -> Void = { [weak self] event in
            self?.selection.select(event)
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
            // Stack gaps come from the model's own metrics — the same
            // instance the keyboard navigator reconstructs frames from,
            // so drawn and navigated geometry cannot diverge.
            rowStack.spacing = model.metrics.spaceSpacing
            return rowStack
        }

        let stack = NSStackView(views: rowViews.isEmpty ? [makeEmptyLabel()] : rowViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = model.metrics.rowSpacing
        let inset = model.metrics.contentInset
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)

        // The footer bar under the rows — GNOME's `createFooter`, shown in
        // the empty state too (the GNOME container always appends it after
        // the rows element). Its custom top gap is the GNOME footer margin,
        // tighter than the row spacing; pinning the trailing edge stretches
        // the footer to the width of the widest row, so the label centering
        // and the right-aligned gear span the whole panel.
        if let lastView = stack.arrangedSubviews.last {
            stack.setCustomSpacing(PanelMetrics.footerMarginTop, after: lastView)
        }
        let footer = makeFooter()
        stack.addArrangedSubview(footer)
        footer.trailingAnchor.constraint(
            equalTo: stack.trailingAnchor, constant: -inset
        ).isActive = true
        return stack
    }

    /// The footer: a centered app-name label and a right-aligned settings
    /// gear (the GNOME footer's spacer/label/button row; AppKit centers
    /// the label absolutely, so no balancing left spacer is needed).
    ///
    /// The gear is deliberately *not* part of the keyboard navigation:
    /// the GNOME navigator traverses only the layout buttons, and the
    /// settings shortcut (⌘,) already covers the keyboard path — the
    /// gear mirrors that and stays mouse-only.
    private func makeFooter() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Sutto")
        label.font = .systemFont(ofSize: PanelMetrics.footerLabelFontSize)
        label.textColor = PanelPalette.footerText
        label.translatesAutoresizingMaskIntoConstraints = false
        // Decorative branding; the panel window is already named.
        label.setAccessibilityElement(false)

        let gear = FooterSettingsButton { [weak self] in
            // The GNOME gear opens preferences and hides in the same
            // gesture (`openPreferences(); hide()`) — the exact pairing of
            // the ⌘, path, including landing on the last-used tab.
            self?.hide()
            self?.onOpenSettings?()
        }

        footer.addSubview(label)
        footer.addSubview(gear)
        NSLayoutConstraint.activate([
            footer.heightAnchor.constraint(equalToConstant: PanelMetrics.footerHeight),
            label.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            gear.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            gear.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        return footer
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
        label.font = .systemFont(ofSize: PanelMetrics.emptyLabelFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeBackground(containing stack: NSStackView) -> NSView {
        // The background doubles as the whole-panel hover surface for
        // auto-hide: its tracking area spans the full panel bounds, so
        // moving between the region buttons (which carry their own
        // tracking areas) never counts as leaving the panel — same as the
        // GNOME container's enter/leave events.
        let background = HoverTrackingBackgroundView()
        background.onMouseEntered = { [weak self] in
            guard let self else { return }
            self.apply(self.autoHide.cursorEntered())
        }
        background.onMouseExited = { [weak self] in
            guard let self else { return }
            self.apply(self.autoHide.cursorExited())
        }
        // GNOME's flat, slightly translucent dark with its hairline rim —
        // a plain layer color, deliberately not a blurred vibrancy
        // material (see ``PanelPalette``).
        background.wantsLayer = true
        background.layer?.backgroundColor = PanelPalette.panelBackground.cgColor
        background.layer?.cornerRadius = PanelMetrics.panelCornerRadius
        background.layer?.masksToBounds = true
        background.layer?.borderColor = PanelPalette.panelBorder.cgColor
        background.layer?.borderWidth = PanelMetrics.panelBorderWidth

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

    // MARK: - Auto-hide

    /// Runs an auto-hide policy effect against the panel's one hide timer.
    /// The policy decides; this only schedules and cancels.
    private func apply(_ effect: PanelAutoHidePolicy.Effect) {
        switch effect {
        case .cancelScheduledHide:
            autoHideTimer?.invalidate()
            autoHideTimer = nil
        case .scheduleHide(let delay):
            autoHideTimer?.invalidate()
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) {
                [weak self] _ in
                // Timers scheduled on the main run loop fire on the main
                // thread; the closure is just not statically isolated.
                MainActor.assumeIsolated {
                    self?.autoHideTimerFired()
                }
            }
        }
    }

    private func autoHideTimerFired() {
        autoHideTimer = nil
        // The policy double-checks the hover state (as GNOME does when its
        // timeout fires), so a stale timer cannot hide a hovered panel.
        if autoHide.shouldHideWhenHideTimerFires {
            hide()
        }
    }

    // MARK: - Click outside closes

    /// Installs the mouse-down monitors that close the panel on a click
    /// outside it. The global monitor sees clicks delivered to *other*
    /// apps — for mouse events it needs no Accessibility permission — and
    /// the local monitor covers clicks landing in Sutto's own windows
    /// (which global monitors never report). Both come down in
    /// ``hide()``; `show()` cannot install twice because the toggle path
    /// only shows a hidden panel, and the guard keeps a stray double-show
    /// from stranding an unremovable monitor.
    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let mouseDown: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseDown, handler: {
            [weak self] _ in
            // Global monitor callbacks arrive on the main thread; the
            // handler parameter is just not statically isolated.
            MainActor.assumeIsolated {
                // Any click another app receives is outside the panel.
                self?.hide()
            }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseDown, handler: {
            [weak self] event in
            MainActor.assumeIsolated {
                // Clicks on the panel itself (its regions, its padding)
                // must not close it; clicks on any other Sutto window are
                // outside. The event passes through unchanged either way —
                // observing, not swallowing.
                if let self, event.window !== self.panel {
                    self.hide()
                }
            }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func removeMouseMonitors() {
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors = []
    }
}

/// The footer's settings gear: a template SF Symbol tinted with the
/// footer text color, with the GNOME gear's hover fill (a faint rounded
/// highlight). The AppKit counterpart of the `sutto-settings-icon` button
/// in the GNOME `createFooter` — `gearshape` standing in for
/// `preferences-system-symbolic`.
///
/// Exposed to accessibility as a button titled "Settings" so the e2e
/// harness (and VoiceOver) can find and press it.
private final class FooterSettingsButton: NSButton {
    private let onClick: () -> Void
    private var isHovered = false

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)

        isBordered = false
        setButtonType(.momentaryChange)
        if let gear = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Settings"
        ) {
            gear.isTemplate = true
            image = gear.withSymbolConfiguration(
                NSImage.SymbolConfiguration(
                    pointSize: PanelMetrics.footerIconSize, weight: .regular))
        }
        contentTintColor = PanelPalette.footerText
        toolTip = "Settings"

        wantsLayer = true
        layer?.cornerRadius = PanelMetrics.footerButtonCornerRadius

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(
                equalToConstant: PanelMetrics.footerIconSize
                    + PanelMetrics.footerButtonHorizontalPadding * 2),
            heightAnchor.constraint(
                equalToConstant: PanelMetrics.footerIconSize
                    + PanelMetrics.footerButtonVerticalPadding * 2),
        ])

        target = self
        action = #selector(clicked)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FooterSettingsButton does not support NSCoder")
    }

    /// The title the harness looks up; the visible button is icon-only.
    override func accessibilityTitle() -> String? {
        "Settings"
    }

    // MARK: - Hover feedback

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyStyle()
    }

    private func applyStyle() {
        layer?.backgroundColor =
            isHovered
            ? PanelPalette.footerButtonHoverBackground.cgColor
            : NSColor.clear.cgColor
    }

    @objc private func clicked() {
        onClick()
    }
}

/// The panel background with a whole-panel hover tracking area, reporting
/// enter/exit to the auto-hide policy — the AppKit counterpart of the
/// enter/leave events GNOME connects on its panel container.
private final class HoverTrackingBackgroundView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        // .activeAlways because the panel never activates the app;
        // .inVisibleRect keeps the area matched to the panel bounds through
        // re-layout without manual bookkeeping.
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
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
