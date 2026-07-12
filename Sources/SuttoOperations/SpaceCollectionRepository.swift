import SuttoDomain

/// Persistence boundary for space collections — the generated presets and
/// the user-imported customs — implemented by the infra layer with
/// file-based storage.
///
/// Mirrors `SpaceCollectionRepository` in
/// `operations/layout/space-collection-repository.ts` of the GNOME version,
/// reduced to the slice v0.2 needs: preset and custom collections live in
/// separate documents (the GNOME preset/custom file pair), presets written
/// only by the preset generator, customs only by the importer. The GNOME
/// interface additionally covers per-space enablement updates; those arrive
/// with the settings-screen work.
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

    /// Finds a custom collection by id. Mirrors `findCollectionById` in the
    /// GNOME repository, restricted to custom collections: the mac active
    /// selection only ever points at a custom collection (the presets are
    /// the cleared-selection fallback, not an addressable choice).
    public func findCustomCollection(by id: CollectionId) -> SpaceCollection? {
        loadCustomCollections().first { $0.id == id }
    }
}
