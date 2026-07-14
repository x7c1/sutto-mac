/// Reads whether the macOS built-in edge-tiling behavior
/// (`com.apple.WindowManager` `EnableTilingByEdgeDrag`) is currently active.
///
/// That OS feature — dragging a window to a screen edge to tile it — collides
/// with Sutto's edge-trigger. Sutto cannot change the system setting
/// programmatically, so this seam exists only to *detect* it and let the app
/// guide the user to turn it off.
///
/// Isolated to the main actor because the result drives UI decisions (the
/// status-menu warning), matching ``PermissionChecking``. Implementations
/// must read the value FRESH on every call — the user may toggle it while the
/// app runs, so a cached read would go stale.
@MainActor
public protocol EdgeTilingDetecting {
    /// Whether macOS edge-tiling is enabled right now. A never-toggled
    /// (absent) setting reads as enabled, the Sequoia default.
    func isSystemEdgeTilingEnabled() -> Bool
}
