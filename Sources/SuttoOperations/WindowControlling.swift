import SuttoDomain

/// Control over a captured window, as required by the operations layer and
/// implemented by the infra layer on top of the Accessibility (AX) API.
///
/// The target window is captured *up front* — once, through
/// ``captureFocusedWindow()`` — and then read from and moved through the
/// returned handle. This is deliberate: an earlier design re-resolved the
/// frontmost app's focused window on every call, which let a tool window
/// (the layout panel itself) become its own placement target the moment it
/// took focus. Capturing once, before any such window is shown, removes
/// that whole class of bug — the handle names a fixed window for the rest
/// of the interaction.
///
/// All frames are in AX coordinates: global top-left origin, y growing
/// downward (see ``SuttoDomain/ScreenCoordinateConverter``).
///
/// Isolated to the main actor because the AX calls behind it are made from
/// the main thread.
@MainActor
public protocol WindowControlling {
    /// Captures the frontmost app's focused window as a target handle, or
    /// `nil` when there is no frontmost app, no focused window, or the
    /// window cannot be read (e.g. the Accessibility permission is
    /// missing). The returned handle is opaque to the operations layer;
    /// pass it back to ``frame(of:)`` and ``applyFrame(_:to:)``.
    func captureFocusedWindow() -> TargetWindow?

    /// The current frame of a captured `window`, in AX coordinates, or
    /// `nil` when the frame cannot be read.
    func frame(of window: TargetWindow) -> PixelRect?

    /// Moves and resizes a captured `window` to `frame`, in AX coordinates.
    ///
    /// - Returns: `false` when the window could not be targeted or the AX
    ///   calls failed outright. `true` means the requests were accepted;
    ///   the window may still end up with a deviating frame (apps enforce
    ///   minimum sizes, the system keeps windows clear of the menu bar) —
    ///   the implementation logs the requested versus actual frame.
    @discardableResult
    func applyFrame(_ frame: PixelRect, to window: TargetWindow) -> Bool
}
