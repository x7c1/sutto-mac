import Foundation
import SuttoDomain
import os

/// Backs the Collections section of the settings window: which collections
/// exist, which one is active, selecting another, deleting a custom one,
/// previewing the active collection's spaces, and toggling a space's
/// visibility.
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
    private let environment: MonitorEnvironmentUseCase
    private let metrics: MiniaturePanelModel.Metrics
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "settings")

    /// - Parameter metrics: The structural panel geometry for the space
    ///   preview; the composition root injects the UI layer's tuned
    ///   instance (DesignTokens' `PanelMetrics.structural`) — the same one
    ///   the panel renders with, so the preview miniatures match the panel.
    public init(
        repository: any SpaceCollectionRepository,
        preferences: any PreferencesRepository,
        screens: any ScreenProviding,
        environment: MonitorEnvironmentUseCase,
        metrics: MiniaturePanelModel.Metrics = .default
    ) {
        self.repository = repository
        self.preferences = preferences
        self.screens = screens
        self.environment = environment
        self.metrics = metrics
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
    /// any radio persists that collection's id. The selection is also
    /// recorded against the *current monitor environment*, so returning to
    /// this display setup later restores it automatically.
    public func select(_ entry: CollectionSettingsEntry) {
        switch entry.kind {
        case .preset(let id), .custom(let id):
            preferences.setActiveCollectionId(id)
            environment.recordActiveCollection(id)
            logger.info("active collection selected: \(id.description, privacy: .public)")
        }
    }

    /// The preview of the collection the panel currently shows — the same
    /// resolution the panel applies, so the preview and the panel always
    /// agree on which collection is on display. `nil` only when nothing
    /// resolves at all (no stored presets and no selection), which the
    /// launch-time preset generation makes practically unreachable.
    ///
    /// Rebuilt from the repository on every call, so a toggle, an import,
    /// or a selection change is reflected on the next refresh — the GNOME
    /// preview reloads the collection from file the same way
    /// (`findCollectionById` before `updatePreview`).
    public func previewModel() -> SpacePreviewModel? {
        guard
            let collection = repository.activeCollection(
                activeId: preferences.activeCollectionId(),
                screens: screens.screens()
            )
        else { return nil }
        return SpacePreviewModel.make(
            collection: collection,
            screens: screens.screens(),
            environments: environment.storedEnvironments(),
            metrics: metrics
        )
    }

    /// Flips the space's visibility in the panel and persists the result —
    /// generated presets and imported customs alike, through
    /// ``SpaceCollectionRepository/updateSpaceEnabled(collectionId:spaceId:enabled:)``.
    ///
    /// The current state is re-read from the repository rather than taken
    /// from the caller, so a stale preview cannot un-toggle a change made
    /// elsewhere. Disabling the last enabled space is allowed, like the
    /// GNOME preferences: the panel then shows its "no spaces" message.
    /// Unknown ids log and no-op (the GNOME `updateSpaceEnabled` returns
    /// `false` the same way).
    public func toggleSpace(collectionId: CollectionId, spaceId: SpaceId) throws {
        guard
            let collection = repository.findCollection(by: collectionId),
            let space = collection.space(withId: spaceId)
        else {
            logger.warning(
                """
                space to toggle not found: \(spaceId.description, privacy: .public) \
                in \(collectionId.description, privacy: .public)
                """)
            return
        }
        let enabled = !space.enabled
        try repository.updateSpaceEnabled(
            collectionId: collectionId, spaceId: spaceId, enabled: enabled)
        logger.info(
            """
            space \(spaceId.description, privacy: .public) \
            \(enabled ? "enabled" : "disabled", privacy: .public) \
            in \(collectionId.description, privacy: .public)
            """)
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
            // The current environment's memory of the deleted collection
            // goes too, so returning to this setup later does not restore
            // a dead id.
            environment.recordActiveCollection(nil)
        }
        logger.info("deleted custom collection \"\(deleted.name, privacy: .public)\"")
    }
}
