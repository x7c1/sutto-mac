/// The geometry the settings window's space preview renders: every space of
/// the selected collection — disabled ones included — as the same miniature
/// the layout panel draws, plus the enabled flag the view dims by.
///
/// This is the macOS counterpart of the preview pane in the GNOME
/// preferences (`prefs/spaces-page.ts`): where the panel filters disabled
/// spaces out (``MiniaturePanelModel``), the preview keeps them, rendered
/// at a reduced opacity and clickable to toggle. The miniature geometry
/// itself is shared with the panel
/// (``MiniaturePanelModel/miniature(for:arrangement:)``), so a space looks
/// identical in the preview and on the panel.
public struct SpacePreviewModel: Equatable, Sendable {
    /// One space in the preview: the panel's miniature plus the enabled
    /// state the toggle flips.
    public struct Entry: Equatable, Sendable {
        /// Whether the space currently participates in the panel. Disabled
        /// entries render at ``Metrics/disabledOpacity``.
        public let enabled: Bool

        /// The space's miniature, identical to the panel's rendering.
        public let miniature: MiniaturePanelModel.SpaceMiniature

        public init(enabled: Bool, miniature: MiniaturePanelModel.SpaceMiniature) {
            self.enabled = enabled
            self.miniature = miniature
        }
    }

    /// One horizontal row of preview entries, mirroring the collection's
    /// row structure.
    public struct Row: Equatable, Sendable {
        public let spaces: [Entry]

        public init(spaces: [Entry]) {
            self.spaces = spaces
        }
    }

    /// The collection the preview shows — the toggle targets this id.
    public let collectionId: CollectionId

    /// The rows to render, top to bottom. Empty when the collection has no
    /// spaces (the GNOME preview then shows "No spaces in this
    /// collection").
    public let rows: [Row]

    /// The structural metrics the miniatures were built with, carried on
    /// the output like ``MiniaturePanelModel/metrics`` so the settings
    /// preview stacks read the exact instance that shaped the geometry.
    public let panelMetrics: MiniaturePanelModel.Metrics

    public init(
        collectionId: CollectionId, rows: [Row],
        panelMetrics: MiniaturePanelModel.Metrics = .default
    ) {
        self.collectionId = collectionId
        self.rows = rows
        self.panelMetrics = panelMetrics
    }

    /// Opacity rules shared with the GNOME preview (`ENABLED_OPACITY`,
    /// `DISABLED_OPACITY`, and `HOVER_OPACITY_CHANGE` in
    /// `prefs/spaces-page.ts`).
    public enum Metrics {
        /// Base opacity of an enabled space.
        public static let enabledOpacity: Double = 1.0

        /// Base opacity of a disabled space.
        public static let disabledOpacity: Double = 0.35

        /// How far hovering moves the opacity toward the other state
        /// (darkening enabled spaces, lightening disabled ones), so the
        /// hover feedback previews what a click would do.
        public static let hoverOpacityChange: Double = 0.15

        /// Base opacity for a space's current enabled state.
        public static func baseOpacity(enabled: Bool) -> Double {
            enabled ? enabledOpacity : disabledOpacity
        }

        /// Hovered opacity for a space's current enabled state.
        public static func hoverOpacity(enabled: Bool) -> Double {
            enabled
                ? enabledOpacity - hoverOpacityChange
                : disabledOpacity + hoverOpacityChange
        }
    }

    /// Builds the preview model for `collection` on the given screens.
    ///
    /// - Disabled spaces are kept (unlike the panel's
    ///   ``MiniaturePanelModel/make(collection:screens:environments:)``);
    ///   only rows with no spaces at all are dropped, like the GNOME
    ///   preview's `updatePreview` skipping empty rows.
    /// - Each space renders with the display arrangement for *its own*
    ///   display count — the GNOME `getMonitorsForSpace`, which resolves
    ///   monitors per space rather than per collection — consulting the
    ///   stored monitor `environments` when the count differs from the
    ///   connected screens, exactly like the panel.
    public static func make(
        collection: SpaceCollection, screens: [Screen],
        environments: [MonitorEnvironment] = [],
        metrics: MiniaturePanelModel.Metrics = .default
    ) -> SpacePreviewModel {
        let rows = collection.rows
            .filter { !$0.spaces.isEmpty }
            .map { row in
                Row(
                    spaces: row.spaces.map { space in
                        let arrangement = PanelDisplayArrangement.resolve(
                            screens: screens,
                            displayCount: max(space.displays.count, 1),
                            environments: environments
                        )
                        return Entry(
                            enabled: space.enabled,
                            miniature: MiniaturePanelModel.miniature(
                                for: space, arrangement: arrangement, metrics: metrics)
                        )
                    })
            }
        return SpacePreviewModel(
            collectionId: collection.id, rows: rows, panelMetrics: metrics)
    }
}
