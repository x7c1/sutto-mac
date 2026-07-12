import SuttoDomain

/// Resolves the layout groups the panel shows: the active collection's
/// panel projection, or the generated preset for the current monitor
/// configuration when no collection applies.
///
/// Mirrors `getActiveSpaceCollection` in the GNOME
/// `SpaceCollectionOperations` (`operations/layout/space-collection-operations/index.ts`):
/// resolve the stored active id, and when it is unset or stale fall back to
/// a preset collection. The GNOME fallback is the *first* stored preset
/// (its preferences let the user activate any generated preset explicitly);
/// the mac settings expose a single "Presets" entry instead, so the
/// fallback picks the preset generated for the current monitor count and
/// type — a standard display gets "N Monitor(s) - Standard", an ultrawide
/// (≥ 21:9, ``SuttoDomain/MonitorType``) gets the wide preset. When that
/// exact preset is missing (e.g. monitors changed and no ensure ran yet),
/// the first stored preset stands in, which is the GNOME behavior.
///
/// The panel calls this on every show, so an import (or a selection
/// change) is reflected the next time the panel opens — the GNOME panel
/// reloads the active collection on show the same way.
@MainActor
public final class ActiveLayoutGroupsUseCase {
    private let repository: any SpaceCollectionRepository
    private let preferences: any PreferencesRepository
    private let screens: any ScreenProviding

    public init(
        repository: any SpaceCollectionRepository,
        preferences: any PreferencesRepository,
        screens: any ScreenProviding
    ) {
        self.repository = repository
        self.preferences = preferences
        self.screens = screens
    }

    /// The layout groups the panel should render right now.
    public func activeLayoutGroups() -> [LayoutGroup] {
        guard
            let id = preferences.activeCollectionId(),
            let collection = repository.findCustomCollection(by: id)
        else {
            guard let preset = fallbackPreset() else { return [] }
            return LayoutPanelProjection.layoutGroups(in: preset)
        }
        return LayoutPanelProjection.layoutGroups(in: collection)
    }

    /// The generated preset matching the current monitor configuration,
    /// classified by the primary display's aspect ratio; the first stored
    /// preset when no name matches, `nil` when none are stored (the ensure
    /// never ran or could not save — the panel renders empty).
    private func fallbackPreset() -> SpaceCollection? {
        let presets = repository.loadPresetCollections()
        let screens = screens.screens()
        guard let primary = screens.first else { return presets.first }

        let name = PresetGenerator.presetName(
            monitorCount: screens.count,
            monitorType: MonitorType.classify(
                width: primary.frame.width, height: primary.frame.height)
        )
        return presets.first { $0.name == name } ?? presets.first
    }
}
