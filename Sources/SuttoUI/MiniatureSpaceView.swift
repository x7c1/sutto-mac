import AppKit
import SuttoDomain

/// Fixed colors for the miniature panel content. The panel background is
/// an `NSVisualEffectView` with the `hudWindow` material, which is dark in
/// both system appearances, so these do not react to the appearance — the
/// same fixed dark palette the GNOME panel uses (`ui/constants.ts`).
enum MiniaturePalette {
    static let spaceBackground = NSColor.white.withAlphaComponent(0.08)
    static let displayBackground = NSColor.black.withAlphaComponent(0.35)
    static let regionBackground = NSColor.white.withAlphaComponent(0.15)
    static let regionBackgroundHovered = NSColor.white.withAlphaComponent(0.30)
    static let regionBorder = NSColor.white.withAlphaComponent(0.30)
    static let regionBorderHovered = NSColor.white.withAlphaComponent(0.60)
    static let regionBorderFocused = NSColor.white.withAlphaComponent(0.90)
    static let regionLabel = NSColor.white.withAlphaComponent(0.90)
    static let menuBarStrip = NSColor(white: 0.8, alpha: 0.9)
    static let displayNumber = NSColor.white.withAlphaComponent(0.90)
    static let displayNumberBackground = NSColor.black.withAlphaComponent(0.60)

    /// Opacity for displays that are not connected right now, mirroring
    /// `INACTIVE_OPACITY` (100/255) in the GNOME miniature display.
    static let disconnectedAlpha: CGFloat = 0.4
}

/// One space's miniature: all displays in their physical arrangement, as
/// computed by ``SuttoDomain/MiniaturePanelModel``. The AppKit counterpart
/// of the GNOME `createMiniatureSpaceView`.
///
/// The view is flipped so the model's top-left-origin frames apply
/// directly, and it is sized by Auto Layout constraints to exactly the
/// model's dimensions — the children are positioned with plain frames.
final class MiniatureSpaceView: NSView {
    /// The display miniatures, in the model's display order — the panel
    /// walks these to map keyboard-focus coordinates onto region buttons.
    let displayViews: [MiniatureDisplayView]

    /// - Parameters:
    ///   - space: The space miniature to render.
    ///   - index: Zero-based position of the space in reading order, used
    ///     for the accessibility label ("Space 1", "Space 2", …).
    ///   - onRegionClicked: Called with the clicked region's selection
    ///     event.
    init(
        space: MiniaturePanelModel.SpaceMiniature,
        index: Int,
        onRegionClicked: @escaping (LayoutSelectedEvent) -> Void
    ) {
        let showsDisplayNumbers = space.displays.count > 1
        self.displayViews = space.displays.map { display in
            MiniatureDisplayView(
                display: display,
                showsDisplayNumber: showsDisplayNumbers,
                onRegionClicked: onRegionClicked
            )
        }
        super.init(frame: NSRect(x: 0, y: 0, width: space.width, height: space.height))
        wantsLayer = true
        layer?.backgroundColor = MiniaturePalette.spaceBackground.cgColor
        layer?.cornerRadius = 6

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: space.width),
            heightAnchor.constraint(equalToConstant: space.height),
        ])

        for displayView in displayViews {
            addSubview(displayView)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Space \(index + 1)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MiniatureSpaceView does not support NSCoder")
    }

    /// Flipped so the model's top-left-origin display frames position the
    /// subviews without conversion.
    override var isFlipped: Bool { true }
}

/// One display inside a space miniature, containing the clickable layout
/// regions. The AppKit counterpart of the GNOME `createMiniatureDisplayView`.
final class MiniatureDisplayView: NSView {
    /// The layout region buttons, in the model's region order — the panel
    /// walks these to map keyboard-focus coordinates onto buttons.
    let regionButtons: [LayoutRegionButton]

    init(
        display: MiniaturePanelModel.DisplayMiniature,
        showsDisplayNumber: Bool,
        onRegionClicked: @escaping (LayoutSelectedEvent) -> Void
    ) {
        self.regionButtons = display.regions.map { region in
            LayoutRegionButton(
                region: region,
                displayKey: display.key,
                onClick: onRegionClicked
            )
        }
        super.init(
            frame: NSRect(
                x: display.frame.x, y: display.frame.y,
                width: display.frame.width, height: display.frame.height))
        wantsLayer = true
        layer?.backgroundColor = MiniaturePalette.displayBackground.cgColor
        layer?.cornerRadius = 4
        layer?.masksToBounds = true

        for button in regionButtons {
            button.isEnabled = display.isConnected
            addSubview(button)
        }

        // The primary display carries a light strip along its top edge —
        // the menu bar, the way the GNOME miniature (and Ubuntu's Displays
        // settings) marks the primary monitor.
        if display.isPrimary {
            let strip = NSView(
                frame: NSRect(x: 0, y: 0, width: display.frame.width, height: 3))
            strip.wantsLayer = true
            strip.layer?.backgroundColor = MiniaturePalette.menuBarStrip.cgColor
            addSubview(strip)
        }

        if showsDisplayNumber {
            addSubview(makeDisplayNumberLabel(for: display))
        }

        if !display.isConnected {
            // Grayed out and (via the buttons' isEnabled above)
            // non-clickable, like the GNOME panel's inactive monitors.
            alphaValue = MiniaturePalette.disconnectedAlpha
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(Self.accessibilityLabel(forDisplayKey: display.key))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MiniatureDisplayView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    /// The AX label for a display miniature: "Display 1" for key "0", and
    /// so on — the 1-based numbering the GNOME miniature shows in its
    /// corner label. The e2e harness navigates by these labels.
    static func accessibilityLabel(forDisplayKey key: String) -> String {
        let number = PanelDisplayKey.screenIndex(for: key).map { $0 + 1 }
        return "Display \(number.map(String.init) ?? key)"
    }

    /// The 1-based display number badge in the bottom-left corner, shown
    /// only in multi-display arrangements (GNOME behavior).
    private func makeDisplayNumberLabel(
        for display: MiniaturePanelModel.DisplayMiniature
    ) -> NSTextField {
        let number = PanelDisplayKey.screenIndex(for: display.key).map { $0 + 1 }
        let label = NSTextField(labelWithString: number.map(String.init) ?? display.key)
        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.textColor = MiniaturePalette.displayNumber
        label.wantsLayer = true
        label.layer?.backgroundColor = MiniaturePalette.displayNumberBackground.cgColor
        label.layer?.cornerRadius = 2
        label.alignment = .center
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 6, height: label.frame.height)
        let margin: CGFloat = 3
        label.frame = NSRect(
            x: margin,
            y: frame.height - size.height - margin,
            width: size.width,
            height: size.height
        )
        // Decorative: the display's AX label already names the display.
        label.setAccessibilityElement(false)
        return label
    }
}

/// A clickable layout region inside a display miniature: a bordered shape
/// proportional to the real layout, labeled when the text fits and always
/// carrying a tooltip. The AppKit counterpart of the GNOME
/// `createLayoutButton`.
///
/// Hover feedback follows the GNOME style priority (hover beats the normal
/// style; the selected state arrives with layout history, deferred within
/// v0.3). Exposed to accessibility as a button titled with the layout
/// label even when the visible text is dropped — keyboard navigation and
/// the e2e harness depend on the title.
///
/// Keyboard focus and mouse hover are independent, the GNOME interplay
/// (`layout-button.ts`, whose enter/leave handlers never touch the
/// keyboard-focus flag): hovering another region highlights it *without*
/// moving or clearing the keyboard focus, so both highlights can be on
/// screen at once, and un-hovering a focused region leaves its focus style
/// intact. The focused style shares the hover background (in GNOME the two
/// styles are identical) but carries a brighter, thicker border so the
/// keyboard position stays distinguishable next to a hover highlight.
final class LayoutRegionButton: NSButton {
    let layout: Layout
    let displayKey: String

    /// Whether the panel's keyboard navigation focuses this region. Set by
    /// the panel only — mouse events never change it.
    var isKeyboardFocused = false {
        didSet { applyStyle() }
    }

    private let onClick: (LayoutSelectedEvent) -> Void
    private var isHovered = false

    private static let borderWidth: CGFloat = 1
    private static let focusedBorderWidth: CGFloat = 2

    private static let labelFont = NSFont.systemFont(ofSize: 10)
    private static let labelPadding: CGFloat = 4

    init(
        region: MiniaturePanelModel.Region,
        displayKey: String,
        onClick: @escaping (LayoutSelectedEvent) -> Void
    ) {
        self.layout = region.layout
        self.displayKey = displayKey
        self.onClick = onClick
        super.init(
            frame: NSRect(
                x: region.frame.x, y: region.frame.y,
                width: region.frame.width, height: region.frame.height))

        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 2
        applyStyle()

        title = Self.fits(label: layout.label, in: frame.size) ? layout.label : ""
        if !title.isEmpty {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byClipping
            attributedTitle = NSAttributedString(
                string: layout.label,
                attributes: [
                    .font: Self.labelFont,
                    .foregroundColor: MiniaturePalette.regionLabel,
                    .paragraphStyle: style,
                ])
        }
        toolTip = layout.label

        target = self
        action = #selector(clicked)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LayoutRegionButton does not support NSCoder")
    }

    /// The layout label, whether or not the visible text fit the region.
    override func accessibilityTitle() -> String? {
        layout.label
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
        guard isEnabled else { return }
        isHovered = true
        applyStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyStyle()
    }

    /// Style priority (the GNOME `getButtonStyle` order with the keyboard
    /// focus folded in): the background highlights on hover *or* focus —
    /// GNOME renders both states with the same style — while the border
    /// grades focus above hover above normal so the keyboard position
    /// stays visible under a concurrent hover.
    private func applyStyle() {
        layer?.backgroundColor =
            (isHovered || isKeyboardFocused
            ? MiniaturePalette.regionBackgroundHovered
            : MiniaturePalette.regionBackground).cgColor
        layer?.borderColor =
            (isKeyboardFocused
            ? MiniaturePalette.regionBorderFocused
            : isHovered
                ? MiniaturePalette.regionBorderHovered
                : MiniaturePalette.regionBorder).cgColor
        layer?.borderWidth = isKeyboardFocused ? Self.focusedBorderWidth : Self.borderWidth
    }

    // MARK: - Click

    @objc private func clicked() {
        onClick(LayoutSelectedEvent(layout: layout, displayKey: displayKey))
    }

    // MARK: - Label fitting

    private static func fits(label: String, in size: NSSize) -> Bool {
        let text = label as NSString
        let bounds = text.size(withAttributes: [.font: labelFont])
        return bounds.width + labelPadding <= size.width
            && bounds.height <= size.height
    }
}
