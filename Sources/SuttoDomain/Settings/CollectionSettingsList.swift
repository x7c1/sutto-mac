/// One row of the settings window's collection list.
public struct CollectionSettingsEntry: Equatable, Sendable {
    /// What the row stands for: the built-in presets, or one imported
    /// custom collection.
    public enum Kind: Equatable, Sendable {
        case presets
        case custom(CollectionId)
    }

    public let kind: Kind

    /// User-visible name ("Presets", or the custom collection's name).
    public let name: String

    /// Whether this row is the collection the panel currently shows.
    public let isActive: Bool

    public init(kind: Kind, name: String, isActive: Bool) {
        self.kind = kind
        self.name = name
        self.isActive = isActive
    }
}

/// Composes the collection list the settings window shows: the built-in
/// presets first, then every imported custom collection, with exactly one
/// entry marked active.
///
/// Mirrors the list pane of the GNOME preferences (`prefs/spaces-page.ts`),
/// which shows a Preset section above a Custom section with a radio per
/// collection. The mac v0.2 presets are a single built-in constant rather
/// than repository state (the preset generator is not ported yet), so the
/// preset section collapses to one fixed "Presets" row.
///
/// Active resolution matches ``ActiveLayoutGroupsUseCase`` (and the GNOME
/// `getActiveSpaceCollection`): a stored id that no longer matches any
/// custom collection degrades to the presets, so the row marked active here
/// is always the collection the panel actually shows.
public enum CollectionSettingsList {
    /// The name of the built-in presets row. The GNOME list titles its
    /// preset section "Preset" and lists generated collections under it;
    /// with a single built-in set, the section title *is* the row.
    public static let presetsEntryName = "Presets"

    public static func entries(
        customCollections: [SpaceCollection], activeId: CollectionId?
    ) -> [CollectionSettingsEntry] {
        let activeCustomId = customCollections.first { $0.id == activeId }?.id
        let presets = CollectionSettingsEntry(
            kind: .presets,
            name: presetsEntryName,
            isActive: activeCustomId == nil
        )
        let customs = customCollections.map { collection in
            CollectionSettingsEntry(
                kind: .custom(collection.id),
                name: collection.name,
                isActive: collection.id == activeCustomId
            )
        }
        return [presets] + customs
    }
}
