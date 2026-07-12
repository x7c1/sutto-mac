/// One row of the settings window's collection list.
public struct CollectionSettingsEntry: Equatable, Sendable {
    /// What the row stands for: one generated preset collection, or one
    /// imported custom collection.
    public enum Kind: Equatable, Sendable {
        case preset(CollectionId)
        case custom(CollectionId)
    }

    public let kind: Kind

    /// User-visible name (the collection's name, e.g. "2 Monitors - Wide").
    public let name: String

    /// Whether this row is the collection the panel currently shows.
    public let isActive: Bool

    public init(kind: Kind, name: String, isActive: Bool) {
        self.kind = kind
        self.name = name
        self.isActive = isActive
    }
}

/// Composes the collection list the settings window shows: every generated
/// preset collection first, then every imported custom collection, with
/// exactly one entry marked active.
///
/// Mirrors the list pane of the GNOME preferences (`prefs/spaces-page.ts`),
/// which lists *all* collections in the preset file under a Preset section
/// (no filtering to the current monitor count — presets generated for an
/// earlier arrangement stay selectable) above a Custom section, with a
/// radio per collection and deletion offered only on customs.
///
/// Active resolution matches the panel's (`ActiveLayoutGroupsUseCase` in
/// the operations layer): the stored id when it names a listed collection —
/// preset or custom — otherwise the default preset the caller resolved via
/// ``PresetSelection``, so the row marked active here is always the
/// collection the panel actually shows.
public enum CollectionSettingsList {
    public static func entries(
        presetCollections: [SpaceCollection],
        customCollections: [SpaceCollection],
        activeId: CollectionId?,
        defaultPresetId: CollectionId?
    ) -> [CollectionSettingsEntry] {
        let storedActiveId = (presetCollections + customCollections)
            .first { $0.id == activeId }?.id
        let resolvedActiveId = storedActiveId ?? defaultPresetId

        let presets = presetCollections.map { collection in
            CollectionSettingsEntry(
                kind: .preset(collection.id),
                name: collection.name,
                isActive: collection.id == resolvedActiveId
            )
        }
        let customs = customCollections.map { collection in
            CollectionSettingsEntry(
                kind: .custom(collection.id),
                name: collection.name,
                isActive: collection.id == resolvedActiveId
            )
        }
        return presets + customs
    }
}
