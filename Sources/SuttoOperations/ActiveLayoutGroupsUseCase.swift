import SuttoDomain

/// Resolves the layout groups the panel shows: the active collection's
/// panel projection, or the default preset when no collection is selected.
///
/// Mirrors `getActiveSpaceCollection` in the GNOME
/// `SpaceCollectionOperations` (`operations/layout/space-collection-operations/index.ts`):
/// resolve the stored active id across presets *and* customs (the user
/// selects generated presets explicitly, exactly like the GNOME
/// preferences), and when the id is unset or stale fall back to a preset —
/// ``SuttoDomain/PresetSelection`` picks the one matching the current
/// display arrangement, refining the GNOME `presets[0]` fallback.
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
            let collection = repository.findCollection(by: id)
        else {
            let fallback = PresetSelection.defaultPreset(
                in: repository.loadPresetCollections(),
                screens: screens.screens()
            )
            guard let preset = fallback else { return [] }
            return LayoutPanelProjection.layoutGroups(in: preset)
        }
        return LayoutPanelProjection.layoutGroups(in: collection)
    }
}
