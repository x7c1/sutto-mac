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

    /// Selects the screen a point belongs to, robustly at every boundary.
    ///
    /// Two steps, in order:
    ///
    /// 1. The first screen whose frame ``PixelRect/contains(_:)`` the point.
    ///    Containment is half-open, so a point on the shared edge of two
    ///    adjacent screens (and every interior point) resolves to exactly
    ///    one screen, deterministically — unchanged from before.
    /// 2. Otherwise the screen whose frame is *nearest* to the point
    ///    (minimum ``PixelRect/distance(to:)``). A point on a screen's outer
    ///    edge — e.g. the exact top row (`y == frame.maxY`) of a non-primary
    ///    screen, which the half-open containment excludes — is distance `0`
    ///    from that screen and farther from any other, so it resolves to its
    ///    own screen instead of blindly falling back to the primary.
    ///
    /// Selecting the nearest screen (rather than the primary) is what fixes
    /// the multi-monitor top/right-edge bug: dragging a window to a
    /// secondary screen's very top edge used to resolve to the primary
    /// screen, because no screen's half-open frame *contained* that pixel.
    ///
    /// - Parameters:
    ///   - point: The point to locate, in AppKit coordinates.
    ///   - screens: The screens to choose from; the first is the primary.
    /// - Returns: The chosen screen, or `nil` when `screens` is empty.
    public static func containing(_ point: PixelPoint, in screens: [Screen]) -> Screen? {
        if let exact = screens.first(where: { $0.frame.contains(point) }) {
            return exact
        }
        return screens.min { $0.frame.distance(to: point) < $1.frame.distance(to: point) }
    }
}
