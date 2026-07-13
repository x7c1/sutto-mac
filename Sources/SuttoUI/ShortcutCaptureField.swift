import AppKit
import SuttoDomain

/// A click-to-capture field for keyboard shortcuts: shows the current
/// combo, and after a click waits for the next key press. What counts as a
/// valid press is decided by ``SuttoDomain/ShortcutCapturePolicy`` (Escape
/// cancels, bare modifiers and unmodified keys are ignored); the view only
/// translates events and renders state.
final class ShortcutCaptureField: NSView {
    /// Called with each captured combo. The owner decides what to do with
    /// it (persist, re-register) and then updates ``combo`` — the field
    /// itself never assumes the capture was accepted.
    var onCapture: ((KeyCombo) -> Void)?

    /// The combo the field displays while not capturing.
    var combo: KeyCombo {
        didSet { refreshAppearance() }
    }

    private let label: NSTextField
    private var isCapturing = false {
        didSet { refreshAppearance() }
    }

    init(combo: KeyCombo) {
        self.combo = combo
        label = NSTextField(labelWithString: combo.displayString)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = SettingsMetrics.captureFieldCornerRadius
        layer?.borderWidth = 1

        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(
                greaterThanOrEqualToConstant: SettingsMetrics.captureFieldMinWidth),
            heightAnchor.constraint(equalToConstant: SettingsMetrics.captureFieldHeight),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -16),
        ])
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ShortcutCaptureField does not support NSCoder")
    }

    // MARK: - Capture lifecycle

    /// Refusing first-responder status while idle keeps the field from
    /// being picked as the window's *initial* first responder — otherwise
    /// merely opening the settings window would start a capture. A capture
    /// begins with an explicit click only.
    override var acceptsFirstResponder: Bool { isCapturing }

    override func mouseDown(with event: NSEvent) {
        beginCapture()
    }

    private func beginCapture() {
        isCapturing = true
        if window?.makeFirstResponder(self) != true {
            isCapturing = false
        }
    }

    override func resignFirstResponder() -> Bool {
        isCapturing = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        handleCapture(of: event)
    }

    /// Command-modified presses bypass `keyDown` and arrive as key
    /// equivalents; while capturing they are shortcut input like any other
    /// press, so route them into the same handling.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCapturing, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        handleCapture(of: event)
        return true
    }

    private func handleCapture(of event: NSEvent) {
        let pressed = KeyComboTranslation.combo(from: event)
        switch ShortcutCapturePolicy.outcome(
            forKeyCode: pressed.keyCode, modifiers: pressed.modifiers)
        {
        case .captured(let captured):
            window?.makeFirstResponder(nil)
            onCapture?(captured)
        case .cancelled:
            window?.makeFirstResponder(nil)
        case .ignored:
            break
        }
    }

    // MARK: - Appearance

    private func refreshAppearance() {
        if isCapturing {
            label.stringValue = "Type shortcut…"
            label.textColor = .secondaryLabelColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            label.stringValue = combo.displayString
            label.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    /// Layer colors do not track appearance changes on their own; re-derive
    /// them when the effective appearance flips (light/dark).
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    // MARK: - Accessibility

    // A plain NSView is invisible to assistive technology; exposing the
    // field as a pressable button lets VoiceOver users start a capture the
    // same way a click does.

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? { "Toggle panel shortcut" }

    override func accessibilityValue() -> Any? { label.stringValue }

    override func accessibilityPerformPress() -> Bool {
        beginCapture()
        return isCapturing
    }
}
