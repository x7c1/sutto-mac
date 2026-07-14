import AppKit
import SuttoDomain

/// One space in the settings window's preview: the same miniature the
/// layout panel renders (``MiniatureSpaceView`` over the shared domain
/// geometry), wrapped in a whole-space click target that toggles the
/// space's visibility. The AppKit counterpart of `createClickableSpace` in
/// the GNOME `prefs/spaces-page.ts`.
///
/// The wrapped miniature is purely decorative here: its layout regions do
/// not place windows from the settings window, so the wrapper claims every
/// click for itself (`hitTest`), the region buttons are disabled (which
/// also silences their hover highlight), and the whole subtree is removed
/// from the accessibility hierarchy — the toggle is exposed as a single
/// checkbox instead ("Space 1", "Space 2", …, value tracking the enabled
/// state), which is what the e2e harness flips.
///
/// Enabled/disabled and hover feedback are pure opacity, with the GNOME
/// values (``SuttoDomain/SpacePreviewModel/Metrics``): disabled spaces sit
/// at the dimmed base opacity, and hovering moves the opacity toward the
/// state a click would produce.
final class SpaceToggleButton: NSControl {
    /// The space this toggle flips.
    let spaceId: SpaceId

    private let spaceEnabled: Bool
    private let onToggle: (SpaceId) -> Void

    /// - Parameters:
    ///   - entry: The preview entry to render.
    ///   - index: Zero-based position of the space in reading order, used
    ///     for the accessibility label ("Space 1", "Space 2", …) — the
    ///     same continuous numbering the panel's miniatures carry.
    ///   - onToggle: Called with the space id when the user clicks the
    ///     space (or presses it through accessibility).
    init(
        entry: SpacePreviewModel.Entry,
        index: Int,
        onToggle: @escaping (SpaceId) -> Void
    ) {
        self.spaceId = entry.miniature.spaceId
        self.spaceEnabled = entry.enabled
        self.onToggle = onToggle
        let miniature = MiniatureSpaceView(
            space: entry.miniature,
            index: index,
            onRegionClicked: { _ in }
        )
        super.init(
            frame: NSRect(
                x: 0, y: 0,
                width: entry.miniature.width, height: entry.miniature.height))

        translatesAutoresizingMaskIntoConstraints = false
        addSubview(miniature)
        NSLayoutConstraint.activate([
            miniature.topAnchor.constraint(equalTo: topAnchor),
            miniature.bottomAnchor.constraint(equalTo: bottomAnchor),
            miniature.leadingAnchor.constraint(equalTo: leadingAnchor),
            miniature.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Decorative miniature: no region clicks, no region hover, and no
        // AX presence (the disabled flag is what silences the buttons'
        // hover tracking, which fires regardless of hitTest).
        for button in miniature.displayViews.flatMap(\.regionButtons) {
            button.isEnabled = false
        }
        removeFromAccessibility(miniature)

        alphaValue = SpacePreviewModel.Metrics.baseOpacity(enabled: spaceEnabled)

        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("Space \(index + 1)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SpaceToggleButton does not support NSCoder")
    }

    // MARK: - Whole-space click target

    /// Every point inside the toggle hits the toggle itself, never the
    /// miniature's subviews — the GNOME preview wraps its miniature in one
    /// `Gtk.Button` the same way.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        // Deliberately empty: the toggle fires on mouse-up inside, the
        // standard button gesture (allowing a press to be cancelled by
        // dragging out).
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            toggle()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
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
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
    }

    override func mouseEntered(with event: NSEvent) {
        alphaValue = SpacePreviewModel.Metrics.hoverOpacity(enabled: spaceEnabled)
    }

    override func mouseExited(with event: NSEvent) {
        alphaValue = SpacePreviewModel.Metrics.baseOpacity(enabled: spaceEnabled)
    }

    // MARK: - Accessibility

    /// The checkbox value: 1 when the space is enabled, 0 when disabled.
    override func accessibilityValue() -> Any? {
        spaceEnabled ? 1 : 0
    }

    /// AX press toggles, exactly like a click — the e2e harness drives the
    /// toggle through this action.
    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    private func toggle() {
        onToggle(spaceId)
    }

    /// Removes `view` and its whole subtree from the accessibility
    /// hierarchy. The miniature's own space/display groups and region
    /// buttons describe the *panel's* interaction model; inside the
    /// settings preview the only meaningful element is the toggle itself.
    private func removeFromAccessibility(_ view: NSView) {
        view.setAccessibilityElement(false)
        for subview in view.subviews {
            removeFromAccessibility(subview)
        }
    }
}
