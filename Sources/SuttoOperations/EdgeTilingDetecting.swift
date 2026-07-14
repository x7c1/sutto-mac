import SuttoDomain

/// Reads which macOS built-in window-tiling gestures (in the
/// `com.apple.WindowManager` domain) are currently active:
///
/// - `EnableTilingByEdgeDrag` — "Drag windows to screen edges to tile".
/// - `EnableTopTilingByEdgeDrag` — "Drag windows to menu bar to fill screen".
///
/// Both react at the same window-drag as Sutto's edge-trigger, so with either
/// on, macOS and Sutto fire at once and interfere. Sutto cannot change these
/// system settings programmatically, so this seam exists only to *detect* them
/// and let the app guide the user to turn them off.
///
/// Isolated to the main actor because the result drives UI decisions (the
/// status-menu warning), matching ``PermissionChecking``. Implementations
/// must read the values FRESH on every call — the user may toggle them while
/// the app runs, so a cached read would go stale.
@MainActor
public protocol EdgeTilingDetecting {
    /// The set of conflicting macOS tiling gestures that are enabled right now.
    /// A never-toggled (absent) setting reads as enabled, the Sequoia default.
    func detectConflicts() -> EdgeTilingConflicts
}
