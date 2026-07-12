import SuttoDomain

/// Resolves the miniature panel model the layout panel renders: the active
/// collection (or the default preset when no collection is selected)
/// projected onto the current display arrangement by
/// ``SuttoDomain/MiniaturePanelModel``.
///
/// Collection resolution mirrors `getActiveSpaceCollection` in the GNOME
/// `SpaceCollectionOperations` (`operations/layout/space-collection-operations/index.ts`):
/// resolve the stored active id across presets *and* customs (the user
/// selects generated presets explicitly, exactly like the GNOME
/// preferences), and when the id is unset or stale fall back to a preset —
/// ``SuttoDomain/PresetSelection`` picks the one matching the current
/// display arrangement, refining the GNOME `presets[0]` fallback.
///
/// The panel calls this on every show, so an import (or a selection
/// change, or a display being plugged in) is reflected the next time the
/// panel opens — the GNOME panel reloads the active collection on show the
/// same way.
@MainActor
public final class ActivePanelModelUseCase {
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

    /// The model the panel should render right now. Empty (no rows) when
    /// no collection resolves or every space is disabled.
    public func panelModel() -> MiniaturePanelModel {
        guard let collection = activeCollection() else {
            return MiniaturePanelModel(rows: [])
        }
        return MiniaturePanelModel.make(collection: collection, screens: screens.screens())
    }

    private func activeCollection() -> SpaceCollection? {
        guard
            let id = preferences.activeCollectionId(),
            let collection = repository.findCollection(by: id)
        else {
            return PresetSelection.defaultPreset(
                in: repository.loadPresetCollections(),
                screens: screens.screens()
            )
        }
        return collection
    }
}
