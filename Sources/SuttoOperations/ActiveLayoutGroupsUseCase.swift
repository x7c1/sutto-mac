import SuttoDomain

/// Resolves the layout groups the panel shows: the active collection's
/// panel projection, or the built-in presets when no collection applies.
///
/// Mirrors `getActiveSpaceCollection` in the GNOME
/// `SpaceCollectionOperations` (`operations/layout/space-collection-operations/index.ts`):
/// resolve the stored active id, and when it is unset or stale fall back to
/// the first preset collection. The mac v0.2 counterpart of "first preset"
/// is the injected preset groups (``SuttoDomain/BuiltInPresets``), since
/// the preset generator is not ported yet and presets are not repository
/// state.
///
/// The panel calls this on every show, so an import (or a future selection
/// change) is reflected the next time the panel opens — the GNOME panel
/// reloads the active collection on show the same way.
@MainActor
public final class ActiveLayoutGroupsUseCase {
    private let repository: any SpaceCollectionRepository
    private let preferences: any PreferencesRepository
    private let presetGroups: [LayoutGroup]

    public init(
        repository: any SpaceCollectionRepository,
        preferences: any PreferencesRepository,
        presetGroups: [LayoutGroup]
    ) {
        self.repository = repository
        self.preferences = preferences
        self.presetGroups = presetGroups
    }

    /// The layout groups the panel should render right now.
    public func activeLayoutGroups() -> [LayoutGroup] {
        guard
            let id = preferences.activeCollectionId(),
            let collection = repository.findCustomCollection(by: id)
        else {
            return presetGroups
        }
        return LayoutPanelProjection.layoutGroups(in: collection)
    }
}
