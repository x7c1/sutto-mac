/// The identity of a captured target window — the frontmost application's
/// bundle identifier and the window's title — snapshotted once when the
/// window is captured.
///
/// This is what layout history keys on: which app, and which window within
/// that app. It is a plain value snapshot, deliberately separate from the
/// opaque ``TargetWindow`` handle — the handle names a live AX element used
/// to move and resize the window, whereas this records what that window was
/// at capture time and never changes for the rest of the opening (even if
/// the window's title later does).
///
/// Either field is `nil` when it could not be read: `bundleIdentifier` when
/// the frontmost application exposes none, `title` when the window's AX
/// element has no readable title. A missing bundle identifier does not fail
/// capture — the history layer decides whether to skip recording.
public struct WindowIdentity: Equatable, Sendable {
    /// The bundle identifier of the frontmost application at capture time
    /// (e.g. `"com.apple.Safari"`), or `nil` when it could not be read.
    public let bundleIdentifier: String?

    /// The captured window's title at capture time, or `nil` when the title
    /// could not be read. May be an empty string for a window that reports a
    /// blank title.
    public let title: String?

    public init(bundleIdentifier: String?, title: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
    }
}
