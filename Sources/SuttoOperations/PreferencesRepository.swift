import SuttoDomain

/// Small key-value preferences the app persists separately from the
/// collection files, implemented by the infra layer.
///
/// Mirrors the active-collection slice of the GNOME
/// `PreferencesRepository` (`infra/glib/preferences-repository.ts`), which
/// keeps the `active-space-collection-id` string in GSettings while the
/// collections themselves live in JSON files. macOS preserves that split:
/// `UserDefaults` stands in for GSettings, files for files.
@MainActor
public protocol PreferencesRepository {
    /// The id of the collection the panel should show, or `nil` when the
    /// user has not selected one (or the stored value is invalid) — the
    /// caller then falls back to presets, like the GNOME
    /// `getActiveSpaceCollection`.
    func activeCollectionId() -> CollectionId?

    /// Stores the active collection id; `nil` clears the selection.
    func setActiveCollectionId(_ id: CollectionId?)
}
