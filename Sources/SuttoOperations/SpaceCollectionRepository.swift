import SuttoDomain

/// Persistence boundary for space collections — the generated presets and
/// the user-imported customs — implemented by the infra layer with
/// file-based storage.
///
/// Mirrors `SpaceCollectionRepository` in
/// `operations/layout/space-collection-repository.ts` of the GNOME version:
/// preset and custom collections live in separate documents (the GNOME
/// preset/custom file pair), presets written only by the preset generator,
/// customs only by the importer — with one exception: the settings
/// window's per-space toggle rewrites whichever file holds the space
/// (``updateSpaceEnabled(collectionId:spaceId:enabled:)``), presets
/// included, exactly like the GNOME `updateSpaceEnabled`.
///
/// Isolated to the main actor like the other operations protocols: every
/// caller is a user-gesture-driven UI flow, and the collection files are
/// small.
@MainActor
public protocol SpaceCollectionRepository {
    /// Loads the generated preset collections. Missing or unreadable
    /// storage yields an empty list, mirroring the GNOME repository — the
    /// preset generator then regenerates on the next ensure.
    func loadPresetCollections() -> [SpaceCollection]

    /// Persists the full preset-collection list, replacing whatever was
    /// stored before.
    func savePresetCollections(_ collections: [SpaceCollection]) throws

    /// Loads all custom (user-imported) collections. Missing or unreadable
    /// storage yields an empty list, mirroring the GNOME repository — the
    /// first run has no file, and the app then falls back to presets.
    func loadCustomCollections() -> [SpaceCollection]

    /// Persists the full custom-collection list, replacing whatever was
    /// stored before.
    func saveCustomCollections(_ collections: [SpaceCollection]) throws
}

extension SpaceCollectionRepository {
    /// Appends a new custom collection and persists the result, minting the
    /// ``SuttoDomain/CollectionId`` here — exactly like `addCustomCollection`
    /// of the GNOME `FileSpaceCollectionRepository`, where the repository
    /// (not the importer) assigns the id.
    public func addCustomCollection(name: String, rows: [SpacesRow]) throws -> SpaceCollection {
        let collection = SpaceCollection(id: .generate(), name: name, rows: rows)
        var collections = loadCustomCollections()
        collections.append(collection)
        try saveCustomCollections(collections)
        return collection
    }

    /// Finds a collection by id across presets and customs, presets first.
    /// Mirrors `findCollectionById` in the GNOME repository, which searches
    /// `loadAllCollections()` (presets + customs) — the active selection can
    /// name a generated preset just as well as an imported collection.
    public func findCollection(by id: CollectionId) -> SpaceCollection? {
        loadPresetCollections().first { $0.id == id }
            ?? loadCustomCollections().first { $0.id == id }
    }

    /// Resolves the collection the panel shows right now: `activeId` when
    /// it names a stored collection — preset or custom — otherwise the
    /// default preset for the connected screens. The resolution chain of
    /// the GNOME `getActiveSpaceCollection`, shared by the panel
    /// (`ActivePanelModelUseCase`) and the settings preview so both always
    /// show the same collection.
    public func activeCollection(activeId: CollectionId?, screens: [Screen]) -> SpaceCollection? {
        if let activeId, let collection = findCollection(by: activeId) {
            return collection
        }
        return PresetSelection.defaultPreset(in: loadPresetCollections(), screens: screens)
    }

    /// Persists a space's `enabled` flag, searching the presets first and
    /// the customs second and rewriting whichever file held the space —
    /// the GNOME `updateSpaceEnabled` of the `FileSpaceCollectionRepository`
    /// persists toggles on generated presets and imported customs the same
    /// way.
    ///
    /// - Returns: `false` when no stored collection holds the space (the
    ///   GNOME method logs and returns `false`); the caller decides whether
    ///   that is worth surfacing.
    @discardableResult
    public func updateSpaceEnabled(
        collectionId: CollectionId, spaceId: SpaceId, enabled: Bool
    ) throws -> Bool {
        var presets = loadPresetCollections()
        if let index = presets.firstIndex(where: { $0.id == collectionId }),
            let updated = presets[index].updatingSpace(spaceId, enabled: enabled)
        {
            presets[index] = updated
            try savePresetCollections(presets)
            return true
        }

        var customs = loadCustomCollections()
        if let index = customs.firstIndex(where: { $0.id == collectionId }),
            let updated = customs[index].updatingSpace(spaceId, enabled: enabled)
        {
            customs[index] = updated
            try saveCustomCollections(customs)
            return true
        }
        return false
    }
}
