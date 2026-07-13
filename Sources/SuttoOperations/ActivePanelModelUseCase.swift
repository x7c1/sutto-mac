import SuttoDomain

/// Resolves the miniature panel model the layout panel renders: the active
/// collection (or the default preset when no collection is selected)
/// projected onto the current display arrangement by
/// ``SuttoDomain/MiniaturePanelModel``.
///
/// Collection resolution mirrors `getActiveSpaceCollection` in the GNOME
/// `SpaceCollectionOperations` (`operations/layout/space-collection-operations/index.ts`):
/// resolve the stored active id across presets *and* customs (the user
/// selects generated presets explicitly, exactly like the GNOME
/// preferences), and when the id is unset or stale fall back to a preset —
/// ``SuttoDomain/PresetSelection`` picks the one matching the current
/// display arrangement, refining the GNOME `presets[0]` fallback.
///
/// The panel calls this on every show, so an import (or a selection
/// change, or a display being plugged in) is reflected the next time the
/// panel opens — the GNOME panel reloads the active collection on show the
/// same way.
@MainActor
public final class ActivePanelModelUseCase {
    private let repository: any SpaceCollectionRepository
    private let preferences: any PreferencesRepository
    private let screens: any ScreenProviding
    private let environment: MonitorEnvironmentUseCase
    private let metrics: MiniaturePanelModel.Metrics

    /// - Parameter metrics: The structural panel geometry; the composition
    ///   root injects the UI layer's tuned instance (DesignTokens'
    ///   `PanelMetrics.structural`) so all design values stay editable in
    ///   one file.
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

    /// The model the panel should render right now. Empty (no rows) when
    /// no collection resolves or every space is disabled.
    ///
    /// The stored monitor environments feed the rendering the way the
    /// GNOME panel consults `getMonitorsForRendering`: a collection made
    /// for more displays than are connected renders with the real
    /// geometry that setup had when last seen, disconnected displays
    /// dimmed.
    public func panelModel() -> MiniaturePanelModel {
        guard let collection = activeCollection() else {
            return MiniaturePanelModel(rows: [], metrics: metrics)
        }
        return MiniaturePanelModel.make(
            collection: collection,
            screens: screens.screens(),
            environments: environment.storedEnvironments(),
            metrics: metrics
        )
    }

    private func activeCollection() -> SpaceCollection? {
        repository.activeCollection(
            activeId: preferences.activeCollectionId(),
            screens: screens.screens()
        )
    }
}
