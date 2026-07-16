import SuttoDomain

/// The single window a panel interaction acts on, captured once when the
/// panel (or the settings window) opens and reused for the rest of that
/// opening.
///
/// This is what enforces the "one target per opening" invariant: the panel
/// captures on ``capture()`` *before* it is shown, so it can never capture
/// itself, and both the anchor computation (``PanelPositionUseCase``) and
/// every layout application (``WindowPlacementUseCase``) read the same
/// captured window back through this session instead of re-resolving the
/// frontmost window on their own. The concrete AX element stays behind the
/// opaque ``TargetWindow`` handle, owned by the ``WindowControlling``
/// implementation — this layer only holds the handle.
@MainActor
public final class PanelTargetSession {
    private let windows: WindowControlling
    private var target: TargetWindow?
    private var identity: WindowIdentity?

    public init(windows: WindowControlling) {
        self.windows = windows
    }

    /// Captures the frontmost app's focused window as the target for the
    /// current opening, replacing any previously captured window. Call once
    /// when the panel or settings window opens, before it is shown or made
    /// key. A `nil` capture (no focused window, or the Accessibility
    /// permission is missing) clears the target, so the subsequent
    /// positioning falls back and placement does nothing.
    public func capture() {
        let captured = windows.captureFocusedWindow()
        target = captured
        // Snapshot the identity in the same synchronous step as the capture,
        // so bundle identifier and title name the window at capture time and
        // stay fixed for the opening — matching the one-target invariant.
        identity = captured.map { windows.identity(of: $0) }
    }

    /// The captured window's current frame, in AX coordinates, or `nil`
    /// when nothing is captured or the frame cannot be read.
    public func targetFrame() -> PixelRect? {
        guard let target else { return nil }
        return windows.frame(of: target)
    }

    /// The captured window's identity — bundle identifier and title —
    /// snapshotted at ``capture()`` time, or `nil` when nothing is captured.
    ///
    /// The value is fixed at capture: a later title change on the window
    /// does not affect it, so layout history records against what the window
    /// was when the panel opened. Layout history keys on this; a `nil`
    /// bundle identifier inside the snapshot is the history layer's cue to
    /// skip recording (decided downstream, not here).
    public func targetIdentity() -> WindowIdentity? {
        identity
    }

    /// Applies `frame` to the captured window. Returns `false` when nothing
    /// is captured or the apply failed — the caller logs and moves on.
    @discardableResult
    public func applyFrame(_ frame: PixelRect) -> Bool {
        guard let target else { return false }
        return windows.applyFrame(frame, to: target)
    }
}
