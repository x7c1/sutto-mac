import CoreGraphics

/// Posts a left mouse click to the system HID event stream, as if the user
/// had clicked at that point on screen. The mouse counterpart of
/// ``ShortcutInjector``; requires the Accessibility permission.
@MainActor
enum MouseInjector {
    /// Clicks at `point`, in global display coordinates (top-left origin,
    /// y down — the same space AX frames use, so a point derived from
    /// ``AXClient/frame(of:)`` needs no conversion).
    static func click(at point: CGPoint) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let mouseDown = CGEvent(
                mouseEventSource: source, mouseType: .leftMouseDown,
                mouseCursorPosition: point, mouseButton: .left),
            let mouseUp = CGEvent(
                mouseEventSource: source, mouseType: .leftMouseUp,
                mouseCursorPosition: point, mouseButton: .left)
        else {
            throw E2EFailure("could not create mouse events at \(point)")
        }
        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
    }
}
