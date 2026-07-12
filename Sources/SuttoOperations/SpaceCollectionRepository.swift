import SuttoDomain

/// Persistence boundary for user-managed space collections, implemented by
/// the infra layer with file-based storage.
///
/// Mirrors `SpaceCollectionRepository` in
/// `operations/layout/space-collection-repository.ts` of the GNOME version,
/// reduced to the slice v0.2 needs. The GNOME interface additionally covers
/// preset collections (generated and persisted by its preset generator) and
/// per-space enablement updates; those arrive with the preset-generator and
/// settings-screen work. Until then the built-in presets are a constant
/// (``SuttoDomain/BuiltInPresets``), not repository state.
///
/// Isolated to the main actor like the other operations protocols: every
/// caller is a user-gesture-driven UI flow, and the collection files are
/// small.
@MainActor
public protocol SpaceCollectionRepository {
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
    /// GNOME repository, restricted to custom collections since presets are
    /// not repository state yet.
    public func findCustomCollection(by id: CollectionId) -> SpaceCollection? {
        loadCustomCollections().first { $0.id == id }
    }
}
