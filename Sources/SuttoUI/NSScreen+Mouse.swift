import AppKit

extension NSScreen {
    /// The screen currently containing the mouse pointer, falling back to the
    /// main screen. Used as the anchor to center a window on the active screen
    /// when there is no better anchor (e.g. no focused window is readable), so
    /// callers that share this fallback land consistently.
    static func withMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
    }
}
