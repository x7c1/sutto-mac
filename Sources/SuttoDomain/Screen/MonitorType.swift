/// The preset flavor a monitor calls for: the wide list for ultrawide
/// displays, the standard list for everything else.
///
/// Mirrors `MonitorType` in the GNOME
/// `operations/layout/preset-generator-operations/preset-generator.ts`. The
/// GNOME version generates presets of *both* types and lets the user pick
/// one in preferences; its `preset-config.ts` documents the wide list as
/// meant for aspect ratios ≥ 21:9 but never classifies a display itself.
/// The mac app has a single "Presets" entry instead of a per-preset radio
/// list, so it needs that documented rule as code: ``classify(width:height:)``
/// turns the GNOME comment into the selection rule.
public enum MonitorType: Equatable, Sendable {
    case standard
    case wide

    /// Classifies a display by its aspect ratio: `wide` iff
    /// width : height ≥ 21 : 9 (the boundary itself is wide, matching the
    /// "aspect ratio >= 21:9" rule in the GNOME `preset-config.ts` comment).
    ///
    /// Compares `width * 9` against `height * 21` so the boundary is exact
    /// rather than subject to floating-point division. Degenerate sizes
    /// (zero or negative height, portrait orientations) are standard.
    public static func classify(width: Double, height: Double) -> MonitorType {
        guard height > 0 else { return .standard }
        return width * 9 >= height * 21 ? .wide : .standard
    }
}
