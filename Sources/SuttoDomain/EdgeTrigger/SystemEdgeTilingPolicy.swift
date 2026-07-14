/// The set of macOS built-in window-tiling gestures that collide head-on with
/// Sutto's own edge-trigger. Both gestures live in the
/// `com.apple.WindowManager` preference domain and, when on, react at the same
/// window-drag Sutto does — so macOS and Sutto fire at once and get in each
/// other's way.
public struct EdgeTilingConflicts: Equatable, Sendable {
    /// "Drag windows to screen edges to tile" (`EnableTilingByEdgeDrag`).
    /// Conflicts at the left, right, and corner edges.
    public let edgeTiling: Bool
    /// "Drag windows to menu bar to fill screen" (`EnableTopTilingByEdgeDrag`).
    /// Conflicts at the top edge.
    public let menuBarFill: Bool

    public init(edgeTiling: Bool, menuBarFill: Bool) {
        self.edgeTiling = edgeTiling
        self.menuBarFill = menuBarFill
    }

    /// Whether any conflicting gesture is enabled — the condition that
    /// warrants surfacing the coexistence guidance.
    public var any: Bool { edgeTiling || menuBarFill }
}

/// Pure interpretation of the macOS built-in window-tiling settings in the
/// `com.apple.WindowManager` domain, both of which collide with Sutto's own
/// edge-trigger:
///
/// - `EnableTilingByEdgeDrag` — "Drag windows to screen edges to tile".
/// - `EnableTopTilingByEdgeDrag` — "Drag windows to menu bar to fill screen".
///
/// Each raw preference read can be absent: a key is only materialized once the
/// user toggles the matching setting, so a fresh install has no value even
/// though the OS behaves as if it were on. macOS Sequoia ships these
/// default-ON, so a missing value MUST be read as enabled — the same conflict
/// is present. Keeping the rule here (rather than in the infra reader) makes it
/// unit-testable without touching CFPreferences.
public enum SystemEdgeTilingPolicy {
    /// Whether an OS tiling gesture is active, given the raw preference value
    /// (`nil` when the key is absent).
    ///
    /// - `true` → enabled (explicitly on)
    /// - `false` → disabled (the user turned it off)
    /// - `nil` → enabled (absent key, the Sequoia default)
    public static func isEnabled(from rawValue: Bool?) -> Bool {
        rawValue ?? true
    }

    /// Builds the conflict set from the two raw preference reads, applying the
    /// "absent → enabled" rule per key.
    public static func conflicts(
        edgeTilingRawValue: Bool?,
        menuBarFillRawValue: Bool?
    ) -> EdgeTilingConflicts {
        EdgeTilingConflicts(
            edgeTiling: isEnabled(from: edgeTilingRawValue),
            menuBarFill: isEnabled(from: menuBarFillRawValue)
        )
    }
}
