/// Picks the *default* preset — the one shown when the user has not
/// selected a collection (or the stored selection is stale).
///
/// The GNOME version falls back to its first stored preset
/// (`getActiveSpaceCollection` in
/// `operations/layout/space-collection-operations/index.ts` returning
/// `presets[0]`) and otherwise relies on the user activating a preset
/// explicitly in preferences. The mac app has the same explicit selection,
/// so ``MonitorType/classify(width:height:)`` is *not* a selector — it only
/// refines this default: instead of blindly taking the first preset, the
/// default is the preset generated for the current monitor count and the
/// primary display's aspect class, degrading to the first stored preset
/// when no name matches (the GNOME behavior).
public enum PresetSelection {
    /// The default preset for the given display arrangement: the preset
    /// named for (count, primary display's ``MonitorType``), else the first
    /// stored preset, else `nil` when none are stored.
    public static func defaultPreset(
        in presets: [SpaceCollection], screens: [Screen]
    ) -> SpaceCollection? {
        guard let primary = screens.first else { return presets.first }

        let name = PresetGenerator.presetName(
            monitorCount: screens.count,
            monitorType: MonitorType.classify(
                width: primary.frame.width, height: primary.frame.height)
        )
        return presets.first { $0.name == name } ?? presets.first
    }
}
