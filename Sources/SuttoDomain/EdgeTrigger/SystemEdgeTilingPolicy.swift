/// Pure interpretation of the macOS built-in edge-tiling setting
/// (`com.apple.WindowManager` `EnableTilingByEdgeDrag`), which collides
/// head-on with Sutto's own edge-trigger.
///
/// The raw preference read can be absent: the key is only materialized once
/// the user toggles the setting, so a fresh install has no value even though
/// the OS behaves as if it were on. macOS Sequoia ships this default-ON, so
/// a missing value MUST be read as enabled — the same conflict is present.
/// Keeping the rule here (rather than in the infra reader) makes it
/// unit-testable without touching CFPreferences.
public enum SystemEdgeTilingPolicy {
    /// Whether the OS edge-tiling behavior is active, given the raw
    /// preference value (`nil` when the key is absent).
    ///
    /// - `true` → enabled (explicitly on)
    /// - `false` → disabled (the user turned it off)
    /// - `nil` → enabled (absent key, the Sequoia default)
    public static func isEnabled(from rawValue: Bool?) -> Bool {
        rawValue ?? true
    }
}
