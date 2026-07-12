import Foundation
import SuttoDomain
import os

/// Backs the Collections section of the settings window: which collections
/// exist, which one is active, selecting another, and deleting a custom one.
///
/// Mirrors the collection management of the GNOME preferences
/// (`prefs/spaces-page.ts` over its `SpaceCollectionOperations`): a radio
/// list of every generated preset plus every custom collection, where
/// selection is explicit — presets included — and deletion is offered only
/// on customs. Deleting the active custom collection falls back to the
/// presets: GNOME re-points the active id at its first preset; the mac app
/// clears the stored id instead, which resolves to the *default* preset
/// (``SuttoDomain/PresetSelection``, the fitting preset for the current
/// displays) — the same "back to presets" outcome, without pinning a
/// selection the user never made.
@MainActor
public final class CollectionSettingsUseCase {
    private let repository: any SpaceCollectionRepository
    private let preferences: any PreferencesRepository
    private let screens: any ScreenProviding
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "settings")

    public init(
        repository: any SpaceCollectionRepository,
        preferences: any PreferencesRepository,
        screens: any ScreenProviding
    ) {
        self.repository = repository
        self.preferences = preferences
        self.screens = screens
    }

    /// The rows the settings list shows, presets first, exactly one active.
    /// With no explicit selection the default preset row is the active one
    /// — the same resolution the panel applies.
    public func entries() -> [CollectionSettingsEntry] {
        let presets = repository.loadPresetCollections()
        return CollectionSettingsList.entries(
            presetCollections: presets,
            customCollections: repository.loadCustomCollections(),
            activeId: preferences.activeCollectionId(),
            defaultPresetId: PresetSelection.defaultPreset(
                in: presets, screens: screens.screens())?.id
        )
    }

    /// Makes `entry` the active collection by storing its id — preset and
    /// custom rows alike, matching the GNOME preferences where activating
    /// any radio persists that collection's id.
    public func select(_ entry: CollectionSettingsEntry) {
        switch entry.kind {
        case .preset(let id), .custom(let id):
            preferences.setActiveCollectionId(id)
            logger.info("active collection selected: \(id.description, privacy: .public)")
        }
    }

    /// Deletes the custom collection with `id`. Deleting the active
    /// collection also clears the stored active id, so the panel falls back
    /// to the default preset. Deleting an id that no longer exists is a
    /// no-op (the GNOME `deleteCustomCollection` logs and returns false).
    public func deleteCollection(_ id: CollectionId) throws {
        var collections = repository.loadCustomCollections()
        guard let index = collections.firstIndex(where: { $0.id == id }) else {
            logger.warning("collection to delete not found: \(id.description, privacy: .public)")
            return
        }

        let deleted = collections.remove(at: index)
        try repository.saveCustomCollections(collections)

        if preferences.activeCollectionId() == id {
            preferences.setActiveCollectionId(nil)
        }
        logger.info("deleted custom collection \"\(deleted.name, privacy: .public)\"")
    }
}
