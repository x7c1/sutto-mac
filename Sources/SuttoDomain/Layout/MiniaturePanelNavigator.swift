/// Keyboard traversal over the miniature layout panel: which region is
/// focused, and where each arrow press moves that focus.
///
/// This is the macOS counterpart of the GNOME version's
/// `MainPanelKeyboardNavigator` (`ui/main-panel/keyboard-navigator.ts`),
/// ported rule for rule:
///
/// - **Arrow movement is geometric, not index-based.** From the focused
///   region's edge midpoint (the right edge when moving right, and so on),
///   the candidate whose *opposite* edge midpoint is nearest by Euclidean
///   distance wins, among candidates lying in the pressed direction (with
///   the same 5-point buffer the GNOME navigator uses). Because the
///   distance is measured across the panel's real geometry, the same rule
///   covers movement within a display, across the displays of a space,
///   across the spaces of a row, and across rows — exactly as in GNOME,
///   where all layout buttons compete in one pool.
/// - **Arrows do not wrap.** At the panel's edge there is no candidate in
///   the pressed direction and the focus stays put.
/// - **Tab cycles with wrap.** Tab order is row index first, then position
///   within the row (left-to-right, top-to-bottom, larger regions before
///   the smaller ones overlapping them), and it wraps around in both
///   directions.
/// - **The panel opens unfocused.** The GNOME navigator gives initial focus
///   to the *selected* layout; selection state (layout history) is deferred
///   within v0.3, so — like the GNOME panel with nothing selected — no
///   region is focused until the first key press, which focuses the
///   top-left region regardless of the pressed direction.
/// - **Disconnected displays are skipped.** Their regions render grayed out
///   and non-clickable, so they are not traversal targets — the GNOME
///   navigator skips non-reactive buttons the same way.
///
/// The navigator is a pure value built from a ``MiniaturePanelModel``: it
/// reconstructs each region's frame in whole-panel coordinates from the
/// model's nested frames and the panel's stacking metrics
/// (``MiniaturePanelModel/Metrics``), so the geometry it navigates is the
/// geometry the panel draws.
public struct MiniaturePanelNavigator: Equatable, Sendable {
    /// A focus position: indices into the ``MiniaturePanelModel`` structure
    /// (row → space → display → region).
    public struct Coordinate: Hashable, Sendable {
        public let row: Int
        public let space: Int
        public let display: Int
        public let region: Int

        public init(row: Int, space: Int, display: Int, region: Int) {
            self.row = row
            self.space = space
            self.display = display
            self.region = region
        }
    }

    /// An arrow-key direction.
    public enum Direction: Sendable, CaseIterable {
        case left, right, up, down
    }

    /// One traversal target: a region's coordinate plus its frame in
    /// whole-panel coordinates (top-left origin) and what selecting it
    /// means.
    private struct Target: Equatable, Sendable {
        let coordinate: Coordinate
        let frame: PixelRect
        let displayKey: String
        let layout: Layout
    }

    /// The GNOME navigator's directional buffer: a candidate counts as
    /// lying in the pressed direction when its edge midpoint is past the
    /// source midpoint minus this slack.
    private static let directionBuffer = 5.0

    /// The GNOME tab order's position tolerance: x/y differences within
    /// this are treated as "same column/row" and fall through to the next
    /// sort key.
    private static let tabOrderTolerance = 5.0

    private let targets: [Target]

    /// Builds the navigator for `model`, reconstructing every connected
    /// region's whole-panel frame from the model's row/space stacking:
    /// rows stack top-aligned below each other with
    /// ``MiniaturePanelModel/Metrics/rowSpacing``, spaces sit left-to-right
    /// within their row with ``MiniaturePanelModel/Metrics/spaceSpacing`` —
    /// the same metrics the panel lays its stack views out with.
    public init(model: MiniaturePanelModel) {
        var targets: [Target] = []
        var rowY = 0.0
        for (rowIndex, row) in model.rows.enumerated() {
            var spaceX = 0.0
            var rowHeight = 0.0
            for (spaceIndex, space) in row.spaces.enumerated() {
                for (displayIndex, display) in space.displays.enumerated()
                where display.isConnected {
                    for (regionIndex, region) in display.regions.enumerated() {
                        targets.append(
                            Target(
                                coordinate: Coordinate(
                                    row: rowIndex, space: spaceIndex,
                                    display: displayIndex, region: regionIndex),
                                frame: PixelRect(
                                    x: spaceX + display.frame.x + region.frame.x,
                                    y: rowY + display.frame.y + region.frame.y,
                                    width: region.frame.width,
                                    height: region.frame.height),
                                displayKey: display.key,
                                layout: region.layout
                            ))
                    }
                }
                // The stacking gaps come from the *model's own* metrics —
                // the same instance the panel's stacks read — so the
                // reconstructed geometry is the drawn geometry by
                // construction, not by two sites agreeing on a constant.
                spaceX += space.width + model.metrics.spaceSpacing
                rowHeight = max(rowHeight, space.height)
            }
            rowY += rowHeight + model.metrics.rowSpacing
        }
        self.targets = targets
    }

    /// Whether the panel has any focusable region at all.
    public var isEmpty: Bool {
        targets.isEmpty
    }

    /// The region the first key press focuses: the top-left one (smallest
    /// y, then smallest x — `findTopLeftButton` in the GNOME navigator).
    /// `nil` when no region is focusable.
    public var firstFocus: Coordinate? {
        targets.min { a, b in
            a.frame.y != b.frame.y ? a.frame.y < b.frame.y : a.frame.x < b.frame.x
        }?.coordinate
    }

    /// Where an arrow press moves the focus.
    ///
    /// - With no current focus, the press only *establishes* focus on the
    ///   top-left region, whatever the direction — the GNOME `moveFocus`
    ///   does exactly this on the first key press.
    /// - Otherwise the nearest region in the pressed direction, or `nil`
    ///   when there is none (the caller keeps the current focus — no
    ///   wrap-around).
    public func move(from current: Coordinate?, direction: Direction) -> Coordinate? {
        guard let current else { return firstFocus }
        guard let source = target(at: current) else { return nil }

        let sourceMidpoint = Self.edgeMidpoint(of: source.frame, direction: direction)
        var closest: Target?
        var minDistance = Double.infinity
        for candidate in targets where candidate.coordinate != current {
            let midpoint = Self.edgeMidpoint(of: candidate.frame, direction: direction.opposite)
            guard Self.isInDirection(midpoint, from: sourceMidpoint, direction: direction) else {
                continue
            }
            let distance = Self.distance(sourceMidpoint, midpoint)
            if distance < minDistance {
                minDistance = distance
                closest = candidate
            }
        }
        return closest?.coordinate
    }

    /// Where a Tab press moves the focus: the next region in tab order
    /// (previous with `reverse`), wrapping around. With no current focus it
    /// starts at the first region (last with `reverse`), like the GNOME
    /// `tabFocus`. `nil` when nothing is focusable.
    public func advance(from current: Coordinate?, reverse: Bool) -> Coordinate? {
        let order = tabOrder()
        guard !order.isEmpty else { return nil }
        guard let current, let index = order.firstIndex(of: current) else {
            return reverse ? order.last : order.first
        }
        let next = reverse ? (index - 1 + order.count) % order.count : (index + 1) % order.count
        return order[next]
    }

    /// What selecting the region at `coordinate` means: its layout and the
    /// display key of the miniature it sits in — the same event a click on
    /// it produces. `nil` for coordinates that are not traversal targets.
    public func selection(at coordinate: Coordinate) -> LayoutSelectedEvent? {
        target(at: coordinate).map {
            LayoutSelectedEvent(layout: $0.layout, displayKey: $0.displayKey)
        }
    }

    // MARK: - Geometry (the GNOME `findNextLayout` rules)

    private func target(at coordinate: Coordinate) -> Target? {
        targets.first { $0.coordinate == coordinate }
    }

    /// The midpoint of the frame's edge facing `direction`.
    private static func edgeMidpoint(of frame: PixelRect, direction: Direction) -> PixelPoint {
        switch direction {
        case .left: PixelPoint(x: frame.x, y: frame.y + frame.height / 2)
        case .right: PixelPoint(x: frame.maxX, y: frame.y + frame.height / 2)
        case .up: PixelPoint(x: frame.x + frame.width / 2, y: frame.y)
        case .down: PixelPoint(x: frame.x + frame.width / 2, y: frame.maxY)
        }
    }

    /// Whether a candidate's edge midpoint lies in the pressed direction
    /// from the source midpoint, with the GNOME buffer of slack.
    private static func isInDirection(
        _ midpoint: PixelPoint, from source: PixelPoint, direction: Direction
    ) -> Bool {
        switch direction {
        case .right: midpoint.x + directionBuffer >= source.x
        case .left: midpoint.x - directionBuffer <= source.x
        case .down: midpoint.y + directionBuffer >= source.y
        case .up: midpoint.y - directionBuffer <= source.y
        }
    }

    private static func distance(_ a: PixelPoint, _ b: PixelPoint) -> Double {
        ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
    }

    /// The flat Tab order (`buildTabOrder` in the GNOME navigator): row
    /// index first, then x within the row, then y (both with a 5-point
    /// tolerance), then larger area first so a region overlapping a smaller
    /// one precedes it.
    private func tabOrder() -> [Coordinate] {
        targets.sorted { a, b in
            if a.coordinate.row != b.coordinate.row {
                return a.coordinate.row < b.coordinate.row
            }
            if abs(a.frame.x - b.frame.x) > Self.tabOrderTolerance {
                return a.frame.x < b.frame.x
            }
            if abs(a.frame.y - b.frame.y) > Self.tabOrderTolerance {
                return a.frame.y < b.frame.y
            }
            return a.frame.width * a.frame.height > b.frame.width * b.frame.height
        }.map(\.coordinate)
    }
}

extension MiniaturePanelNavigator.Direction {
    /// The direction whose edge a candidate presents to a mover: moving
    /// right targets candidates' left edges, and so on.
    fileprivate var opposite: Self {
        switch self {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
    }
}
