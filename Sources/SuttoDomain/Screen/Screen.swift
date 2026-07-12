/// A display, described as plain value types so the domain stays free of
/// AppKit (`NSScreen` never crosses into this layer).
///
/// Both rectangles are in the AppKit global coordinate space: origin at the
/// bottom-left corner of the primary screen, y growing upward. Screens other
/// than the primary can therefore have negative coordinates (a screen below
/// the primary has a negative y, a screen to the left a negative x).
public struct Screen: Equatable, Sendable {
    /// The full frame of the screen.
    public let frame: PixelRect

    /// The frame available to windows (the work area): the full frame minus
    /// the menu bar and the Dock. Mirrors `NSScreen.visibleFrame`.
    public let visibleFrame: PixelRect

    public init(frame: PixelRect, visibleFrame: PixelRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}
