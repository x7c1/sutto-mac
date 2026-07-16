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
    private let session: PanelTargetSession?
    private let history: LayoutHistoryUseCase?

    /// - Parameters:
    ///   - metrics: The structural panel geometry; the composition root
    ///     injects the UI layer's tuned instance (DesignTokens'
    ///     `PanelMetrics.structural`) so all design values stay editable in
    ///     one file.
    ///   - session: The panel's target session, read for the captured
    ///     window's identity when resolving the layout-history recommendation.
    ///     Optional so surfaces that reuse this use case without a captured
    ///     window (the settings preview) simply get no recommendation.
    ///   - history: The layout-history use case that resolves the recommended
    ///     layout. Optional for the same reason as `session`; a recommendation
    ///     is only stamped on the model when both are present.
    public init(
        repository: any SpaceCollectionRepository,
        preferences: any PreferencesRepository,
        screens: any ScreenProviding,
        environment: MonitorEnvironmentUseCase,
        metrics: MiniaturePanelModel.Metrics = .default,
        session: PanelTargetSession? = nil,
        history: LayoutHistoryUseCase? = nil
    ) {
        self.repository = repository
        self.preferences = preferences
        self.screens = screens
        self.environment = environment
        self.metrics = metrics
        self.session = session
        self.history = history
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
        let model = MiniaturePanelModel.make(
            collection: collection,
            screens: screens.screens(),
            environments: environment.storedEnvironments(),
            metrics: metrics
        )
        return model.recommending(recommendedLayout(in: collection))
    }

    /// The layout to recommend for the captured window under `collection`, or
    /// `nil` when no target was captured, no history was configured, or
    /// nothing was learned. Scoped to the collection the panel is showing, so
    /// a recommendation learned under one collection never surfaces under
    /// another (the GNOME per-collection scoping).
    ///
    /// Reads the identity the panel already snapshotted in
    /// ``PanelTargetSession/capture()`` on this opening — the panel captures
    /// before it reads the model, so the identity names the window the panel
    /// is targeting.
    private func recommendedLayout(in collection: SpaceCollection) -> LayoutId? {
        guard let history else { return nil }
        return history.recommendedLayout(for: session?.targetIdentity(), in: collection.id)
    }

    private func activeCollection() -> SpaceCollection? {
        repository.activeCollection(
            activeId: preferences.activeCollectionId(),
            screens: screens.screens()
        )
    }
}
