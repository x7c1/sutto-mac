/// The geometry the miniature layout panel renders: for every enabled space
/// of a collection, a miniature preview of *all* displays in their physical
/// arrangement, each display containing one clickable region per layout of
/// the group assigned to it.
///
/// This is the macOS counterpart of the GNOME version's miniature rendering
/// pipeline (`ui/components/space-dimensions.ts`, `miniature-space.ts`, and
/// `miniature-display.ts`): the same bounding-box math, the same scale rule,
/// and the same margins, computed here as a pure model so the AppKit layer
/// only draws frames it is handed. All frames are in *top-left-origin*
/// coordinates (y growing downward), matching both the GNOME global space
/// and the layout expressions' own orientation; the view layer renders them
/// in flipped views.
public struct MiniaturePanelModel: Equatable, Sendable {
    /// One clickable layout region inside a display miniature.
    public struct Region: Equatable, Sendable {
        /// The layout the region stands for.
        public let layout: Layout

        /// The region's frame within its display miniature (top-left
        /// origin).
        public let frame: PixelRect

        public init(layout: Layout, frame: PixelRect) {
            self.layout = layout
            self.frame = frame
        }
    }

    /// One display inside a space miniature.
    public struct DisplayMiniature: Equatable, Sendable {
        /// The display key (`"0"`, `"1"`, …); see ``PanelDisplayKey``.
        public let key: String

        /// The display's frame within its space miniature (top-left
        /// origin), scaled from the display's actual geometry.
        public let frame: PixelRect

        /// Whether this is the primary display (rendered with a menu-bar
        /// strip, the way the GNOME miniature marks it).
        public let isPrimary: Bool

        /// `false` when the key exceeds the connected screens — the
        /// collection was made for more displays than are attached. The
        /// GNOME panel renders such displays grayed out and non-clickable
        /// (`inactiveMonitorKeys` in its monitor environment operations);
        /// this panel does the same.
        public let isConnected: Bool

        /// The clickable layout regions, in the assigned group's layout
        /// order. Empty when the space assigns no group to this key — the
        /// display still renders, as an empty miniature.
        public let regions: [Region]

        public init(
            key: String, frame: PixelRect, isPrimary: Bool, isConnected: Bool,
            regions: [Region]
        ) {
            self.key = key
            self.frame = frame
            self.isPrimary = isPrimary
            self.isConnected = isConnected
            self.regions = regions
        }
    }

    /// One space's miniature: all displays in their physical arrangement.
    public struct SpaceMiniature: Equatable, Sendable {
        /// Identity of the space this miniature previews.
        public let spaceId: SpaceId

        /// Width of the miniature container in points.
        public let width: Double

        /// Height of the miniature container in points.
        public let height: Double

        /// The display miniatures, ordered by display key.
        public let displays: [DisplayMiniature]

        public init(spaceId: SpaceId, width: Double, height: Double, displays: [DisplayMiniature]) {
            self.spaceId = spaceId
            self.width = width
            self.height = height
            self.displays = displays
        }
    }

    /// One horizontal row of space miniatures, mirroring the collection's
    /// row structure.
    public struct Row: Equatable, Sendable {
        /// The space miniatures in this row, in display order.
        public let spaces: [SpaceMiniature]

        public init(spaces: [SpaceMiniature]) {
            self.spaces = spaces
        }
    }

    /// The rows to render, top to bottom. Empty when every space is
    /// disabled (the panel then shows a "no spaces" message, like the
    /// GNOME panel after filtering).
    public let rows: [Row]

    public init(rows: [Row]) {
        self.rows = rows
    }

    /// Sizing rules shared with the GNOME version's `ui/constants.ts`.
    public enum Metrics {
        /// Maximum width of the widest display in a miniature
        /// (`MAX_MONITOR_DISPLAY_WIDTH`).
        public static let maxDisplayWidth: Double = 240

        /// Maximum height of the tallest display in a miniature
        /// (`MAX_MONITOR_DISPLAY_HEIGHT`).
        public static let maxDisplayHeight: Double = 100

        /// Margin around each display within a space miniature
        /// (`MONITOR_MARGIN`).
        public static let displayMargin: Double = 6

        /// Fallback display size when no screen is attached
        /// (`DEFAULT_MONITOR_WIDTH`/`HEIGHT` in the GNOME domain).
        public static let fallbackDisplaySize = (width: 1920.0, height: 1080.0)

        /// Horizontal gap between the space miniatures of a row. Shared by
        /// the panel's row stacks and ``MiniaturePanelNavigator``, which
        /// reconstructs whole-panel region frames from it — the two must
        /// agree or keyboard focus would navigate a different geometry than
        /// the one drawn.
        public static let spaceSpacing: Double = 6

        /// Vertical gap between rows. Shared with the navigator like
        /// ``spaceSpacing``.
        public static let rowSpacing: Double = 10

        /// Padding between the panel edge and the miniatures. A uniform
        /// translation of everything, so the navigator's relative geometry
        /// is unaffected; kept here so the panel's metrics live in one
        /// place.
        public static let contentInset: Double = 16
    }

    /// Builds the model for `collection` on the given screens.
    ///
    /// - Disabled spaces are filtered out, and rows left empty by the
    ///   filter are dropped (`filterEnabledSpaces` in the GNOME
    ///   `ui/main-panel/index.ts`).
    /// - The displays rendered per space come from
    ///   ``PanelDisplayArrangement/resolve(screens:displayCount:environments:)``,
    ///   consulting `environments` — the stored monitor environments —
    ///   when the collection references more displays than are connected;
    ///   every space in the collection shows the same display arrangement.
    /// - Layouts whose expressions fail to parse are skipped rather than
    ///   failing the whole panel: collections are user-editable JSON, and
    ///   one bad expression should not blank the panel. (The placement
    ///   path logs the same condition when such a layout is applied.)
    public static func make(
        collection: SpaceCollection, screens: [Screen],
        environments: [MonitorEnvironment] = []
    ) -> MiniaturePanelModel {
        let enabledRows = collection.rows
            .map { $0.spaces.filter(\.enabled) }
            .filter { !$0.isEmpty }

        let displayCount = max(
            enabledRows.joined().map { $0.displays.count }.max() ?? 0,
            1
        )
        let arrangement = PanelDisplayArrangement.resolve(
            screens: screens, displayCount: displayCount, environments: environments)

        return MiniaturePanelModel(
            rows: enabledRows.map { spaces in
                Row(spaces: spaces.map { miniature(for: $0, arrangement: arrangement) })
            }
        )
    }

    // MARK: - Per-space geometry

    /// Builds one space's miniature: the GNOME `createMiniatureSpaceView` +
    /// `calculateSpaceDimensions` math, on top-left-origin display frames.
    /// Internal rather than private because ``SpacePreviewModel`` builds the
    /// settings preview from the same geometry — the two surfaces must
    /// render identical miniatures.
    static func miniature(
        for space: Space, arrangement: PanelDisplayArrangement
    ) -> SpaceMiniature {
        let displays = arrangement.displays
        let margin = Metrics.displayMargin

        // Scale so the largest display fits the miniature limits
        // (space-dimensions.ts: scale from the largest referenced monitor;
        // here from the largest rendered display, which is the same set
        // because every space renders the full arrangement).
        let maxWidth = displays.map(\.frame.width).max() ?? 0
        let maxHeight = displays.map(\.frame.height).max() ?? 0
        let scaleByWidth = maxWidth > 0 ? min(Metrics.maxDisplayWidth / maxWidth, 1.0) : 1.0
        let scaleByHeight = maxHeight > 0 ? min(Metrics.maxDisplayHeight / maxHeight, 1.0) : 1.0
        let scale = min(scaleByWidth, scaleByHeight)

        // Bounding box of the arrangement, in real (unscaled) coordinates.
        let minX = displays.map(\.frame.x).min() ?? 0
        let minY = displays.map(\.frame.y).min() ?? 0

        var placed: [DisplayMiniature] = []
        var actualMaxX = 0.0
        var actualMaxY = 0.0
        for display in displays {
            // Shrink each display by the margin and offset it by the same
            // amount, producing a visible gap between adjacent displays
            // (miniature-space.ts does exactly this because its fixed
            // layout ignores CSS padding).
            let frame = PixelRect(
                x: (display.frame.x - minX) * scale + margin,
                y: (display.frame.y - minY) * scale + margin,
                width: display.frame.width * scale - margin,
                height: display.frame.height * scale - margin
            )
            placed.append(
                DisplayMiniature(
                    key: display.key,
                    frame: frame,
                    isPrimary: display.isPrimary,
                    isConnected: display.isConnected,
                    regions: regions(
                        for: space.displays[display.key],
                        displayFrame: frame,
                        workAreaWidth: display.workAreaWidth,
                        workAreaHeight: display.workAreaHeight
                    )
                ))
            actualMaxX = max(actualMaxX, frame.maxX)
            actualMaxY = max(actualMaxY, frame.maxY)
        }

        return SpaceMiniature(
            spaceId: space.id,
            width: actualMaxX + margin,
            height: actualMaxY + margin,
            displays: placed
        )
    }

    /// Resolves a group's layouts to regions within a display miniature.
    ///
    /// Expressions are evaluated against the miniature's scaled size, with
    /// the display's real work-area size as the `screenSize` context so
    /// absolute pixel values shrink proportionally — the same call the
    /// GNOME `createLayoutButton` makes (`evaluate(expr, containerSize,
    /// workArea.width)`).
    private static func regions(
        for group: LayoutGroup?,
        displayFrame: PixelRect,
        workAreaWidth: Double,
        workAreaHeight: Double
    ) -> [Region] {
        guard let group else { return [] }
        return group.layouts.compactMap { layout in
            guard
                let x = evaluate(
                    layout.position.x, container: displayFrame.width, screen: workAreaWidth),
                let y = evaluate(
                    layout.position.y, container: displayFrame.height, screen: workAreaHeight),
                let width = evaluate(
                    layout.size.width, container: displayFrame.width, screen: workAreaWidth),
                let height = evaluate(
                    layout.size.height, container: displayFrame.height, screen: workAreaHeight)
            else { return nil }

            // Round the region's *edges* to whole pixels, not its position
            // and size independently. Tiling layouts define adjacency
            // through expressions (x = 25%, width = 25%, next x = 50%),
            // and per-term rounding — GNOME's Math.round on every value,
            // which `LayoutExpressionEvaluator.evaluate` mirrors — lets
            // the accumulated edge (`round(0.25w) + round(0.25w)`) land a
            // pixel away from the neighbor's own edge (`round(0.5w)`) on
            // fractionally scaled displays, drawing a visible background
            // gap between tiles that should touch (a deliberate fix over
            // GNOME, whose miniatures carry the same seam artifact).
            // Rounding both tiles' shared edge from the same exact value
            // makes adjacency survive rounding by construction.
            let minX = LayoutExpressionEvaluator.roundToPixel(x)
            let minY = LayoutExpressionEvaluator.roundToPixel(y)
            let maxX = LayoutExpressionEvaluator.roundToPixel(x + width)
            let maxY = LayoutExpressionEvaluator.roundToPixel(y + height)
            return Region(
                layout: layout,
                frame: PixelRect(
                    x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            )
        }
    }

    /// Evaluates an expression to an *unrounded* pixel value — the region
    /// computation rounds combined edges instead of individual terms (see
    /// the comment in ``regions(for:displayFrame:workAreaWidth:workAreaHeight:)``).
    private static func evaluate(
        _ expression: String, container: Double, screen: Double
    ) -> Double? {
        guard let parsed = try? LayoutExpressionParser.parse(expression) else { return nil }
        return LayoutExpressionEvaluator.evaluateUnrounded(
            parsed, containerSize: container, screenSize: screen)
    }
}

/// The display arrangement the panel renders miniatures from: which
/// displays exist, where they sit relative to each other, and which of them
/// are actually connected right now.
///
/// This is the macOS counterpart of `getMonitorsForRendering` in the GNOME
/// `operations/monitor/monitor-environment-operations.ts`:
///
/// - When the collection's display count matches the connected screens,
///   the real screens are used, in their real relative arrangement.
/// - Otherwise the stored monitor environments are consulted: the most
///   recently active environment with that display count supplies the real
///   geometry the setup had when last seen, with the keys beyond the
///   connected count marked disconnected — those render grayed out and
///   non-clickable.
/// - With no matching environment a synthetic arrangement is built:
///   `displayCount` displays of the primary screen's size, side by side
///   (the GNOME fallback), disconnected keys marked the same way.
public struct PanelDisplayArrangement: Equatable, Sendable {
    /// One display of the arrangement.
    public struct Display: Equatable, Sendable {
        /// The display key (`"0"`, `"1"`, …); see ``PanelDisplayKey``.
        public let key: String

        /// The display's full frame in a shared top-left-origin coordinate
        /// space (real screens are converted from AppKit coordinates; the
        /// relative arrangement is what matters, not the absolute origin).
        public let frame: PixelRect

        /// Width of the display's work area, used to scale absolute
        /// pixel expressions into the miniature.
        public let workAreaWidth: Double

        /// Height of the display's work area.
        public let workAreaHeight: Double

        /// Whether this is the primary display.
        public let isPrimary: Bool

        /// Whether a screen with this key is currently connected.
        public let isConnected: Bool

        public init(
            key: String, frame: PixelRect, workAreaWidth: Double, workAreaHeight: Double,
            isPrimary: Bool, isConnected: Bool
        ) {
            self.key = key
            self.frame = frame
            self.workAreaWidth = workAreaWidth
            self.workAreaHeight = workAreaHeight
            self.isPrimary = isPrimary
            self.isConnected = isConnected
        }
    }

    /// The displays, ordered by key (`"0"` first).
    public let displays: [Display]

    public init(displays: [Display]) {
        self.displays = displays
    }

    /// Resolves the arrangement for a collection made for `displayCount`
    /// displays on the currently connected `screens` (AppKit coordinates,
    /// primary first — the ``…/ScreenProviding`` order), consulting the
    /// stored monitor `environments` when the counts disagree.
    public static func resolve(
        screens: [Screen], displayCount: Int, environments: [MonitorEnvironment] = []
    ) -> PanelDisplayArrangement {
        if screens.count == displayCount, let primary = screens.first {
            let displays = screens.enumerated().map { index, screen in
                Display(
                    key: PanelDisplayKey.key(forScreenAt: index),
                    frame: ScreenCoordinateConverter.axRect(
                        fromAppKit: screen.frame, primaryScreenFrame: primary.frame),
                    workAreaWidth: screen.visibleFrame.width,
                    workAreaHeight: screen.visibleFrame.height,
                    isPrimary: index == 0,
                    isConnected: true
                )
            }
            return PanelDisplayArrangement(displays: displays)
        }

        // Count mismatch: prefer a stored environment that was seen with
        // exactly displayCount monitors — the GNOME
        // `findEnvironmentForCollection`, most recently active first — so
        // the miniature shows the real geometry that setup had, not a
        // synthetic row. Keys beyond the connected screens render
        // disconnected (`inactiveMonitorKeys` in the GNOME original).
        let candidates = environments.filter { $0.monitors.count == displayCount }
        if let environment = candidates.max(by: { $0.lastActiveAt < $1.lastActiveAt }) {
            let displays = environment.monitors
                .sorted { $0.index < $1.index }
                .map { monitor in
                    Display(
                        key: PanelDisplayKey.key(forScreenAt: monitor.index),
                        // Stored geometry is already top-left-origin; see
                        // ``Monitor``.
                        frame: monitor.geometry,
                        workAreaWidth: monitor.workArea.width,
                        workAreaHeight: monitor.workArea.height,
                        isPrimary: monitor.isPrimary,
                        isConnected: monitor.index < screens.count
                    )
                }
            return PanelDisplayArrangement(displays: displays)
        }

        // No environment either (or no screens at all): synthesize displayCount
        // displays of the primary screen's size, side by side — the GNOME
        // fallback when no stored environment matches.
        let referenceFrame =
            screens.first?.frame
            ?? PixelRect(
                x: 0, y: 0,
                width: MiniaturePanelModel.Metrics.fallbackDisplaySize.width,
                height: MiniaturePanelModel.Metrics.fallbackDisplaySize.height
            )
        let referenceWorkArea = screens.first?.visibleFrame ?? referenceFrame
        let displays = (0..<displayCount).map { index in
            Display(
                key: PanelDisplayKey.key(forScreenAt: index),
                frame: PixelRect(
                    x: Double(index) * referenceFrame.width,
                    y: 0,
                    width: referenceFrame.width,
                    height: referenceFrame.height
                ),
                workAreaWidth: referenceWorkArea.width,
                workAreaHeight: referenceWorkArea.height,
                isPrimary: index == 0,
                isConnected: index < screens.count
            )
        }
        return PanelDisplayArrangement(displays: displays)
    }
}
