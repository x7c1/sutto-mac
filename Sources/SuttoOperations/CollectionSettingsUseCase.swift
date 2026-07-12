import Foundation
import SuttoDomain
import os

/// Backs the Collections section of the settings window: which collections
/// exist, which one is active, selecting another, and deleting a custom one.
///
/// Mirrors the collection management of the GNOME preferences
/// (`prefs/spaces-page.ts` over its `SpaceCollectionOperations`): a radio
/// list of preset + custom collections where selection is explicit, and
/// deleting the active custom collection falls back to the presets. GNOME
/// re-points the active id at its first preset collection in that case; the
/// mac presets are not repository state yet, so the equivalent is clearing
/// the stored id — ``ActiveLayoutGroupsUseCase`` then resolves to the
/// built-in presets.
@MainActor
public final class CollectionSettingsUseCase {
    private let repository: any SpaceCollectionRepository
    private let preferences: any PreferencesRepository
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "settings")

    public init(
        repository: any SpaceCollectionRepository,
        preferences: any PreferencesRepository
    ) {
        self.repository = repository
        self.preferences = preferences
    }

    /// The rows the settings list shows, presets first, exactly one active.
    public func entries() -> [CollectionSettingsEntry] {
        CollectionSettingsList.entries(
            customCollections: repository.loadCustomCollections(),
            activeId: preferences.activeCollectionId()
        )
    }

    /// Makes `entry` the active collection: a custom entry stores its id,
    /// the presets entry clears the stored id (the fallback state).
    public func select(_ entry: CollectionSettingsEntry) {
        switch entry.kind {
        case .presets:
            preferences.setActiveCollectionId(nil)
            logger.info("active collection cleared: falling back to presets")
        case .custom(let id):
            preferences.setActiveCollectionId(id)
            logger.info("active collection selected: \(id.description, privacy: .public)")
        }
    }

    /// Deletes the custom collection with `id`. Deleting the active
    /// collection also clears the stored active id, so the panel falls back
    /// to the presets. Deleting an id that no longer exists is a no-op
    /// (the GNOME `deleteCustomCollection` logs and returns false).
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
