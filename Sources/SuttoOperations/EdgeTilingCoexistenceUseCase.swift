import SuttoDomain

/// Decides whether to warn the user that a macOS built-in window-tiling
/// gesture is on and conflicts with Sutto's edge-trigger.
///
/// The decision is deliberately non-blocking: Sutto keeps its edge-trigger
/// enabled either way and only surfaces guidance. Sutto cannot change the
/// system settings, so all it can do is detect the conflicts and point the
/// user at System Settings.
@MainActor
public final class EdgeTilingCoexistenceUseCase {
    private let detector: any EdgeTilingDetecting

    public init(detector: any EdgeTilingDetecting) {
        self.detector = detector
    }

    /// The conflicting macOS tiling gestures enabled right now. Read fresh
    /// through the detector, so it tracks the user toggling a setting without
    /// a relaunch. Drives the guidance window, which lists the enabled ones.
    public func currentConflicts() -> EdgeTilingConflicts {
        detector.detectConflicts()
    }

    /// Whether to show the coexistence warning: true exactly while any
    /// conflicting macOS tiling gesture is enabled.
    public func shouldWarn() -> Bool {
        currentConflicts().any
    }
}
