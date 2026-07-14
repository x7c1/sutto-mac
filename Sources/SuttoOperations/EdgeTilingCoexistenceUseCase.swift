/// Decides whether to warn the user that macOS's built-in edge-tiling is on
/// and conflicts with Sutto's edge-trigger.
///
/// The decision is deliberately non-blocking: Sutto keeps its edge-trigger
/// enabled either way and only surfaces guidance. Sutto cannot change the
/// system setting, so all it can do is detect the conflict and point the user
/// at System Settings.
@MainActor
public final class EdgeTilingCoexistenceUseCase {
    private let detector: any EdgeTilingDetecting

    public init(detector: any EdgeTilingDetecting) {
        self.detector = detector
    }

    /// Whether to show the coexistence warning: true exactly while macOS
    /// edge-tiling is enabled. Read fresh through the detector, so it tracks
    /// the user toggling the setting without a relaunch.
    public func shouldWarn() -> Bool {
        detector.isSystemEdgeTilingEnabled()
    }
}
