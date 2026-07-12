import SuttoDomain

/// Control over the frontmost app's focused window, as required by the
/// operations layer and implemented by the infra layer on top of the
/// Accessibility (AX) API.
///
/// All frames are in AX coordinates: global top-left origin, y growing
/// downward (see ``SuttoDomain/ScreenCoordinateConverter``).
///
/// Isolated to the main actor because the AX calls behind it are made from
/// the main thread.
@MainActor
public protocol WindowControlling {
    /// The current frame of the frontmost app's focused window, in AX
    /// coordinates, or `nil` when there is no frontmost app, no focused
    /// window, or the frame cannot be read (e.g. the Accessibility
    /// permission is missing).
    func focusedWindowFrame() -> PixelRect?

    /// Moves and resizes the frontmost app's focused window to `frame`, in
    /// AX coordinates.
    ///
    /// - Returns: `false` when no window could be targeted or the AX calls
    ///   failed outright. `true` means the requests were accepted; the
    ///   window may still end up with a deviating frame (apps enforce
    ///   minimum sizes, the system keeps windows clear of the menu bar) —
    ///   the implementation logs the requested versus actual frame.
    @discardableResult
    func applyFrame(_ frame: PixelRect) -> Bool
}
