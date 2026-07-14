import Testing

@testable import SuttoDomain

/// Traversal semantics ported from the GNOME `MainPanelKeyboardNavigator`:
/// midpoint-distance arrow movement over the panel's real geometry, no
/// arrow wrap, wrapping Tab order, top-left first focus, and disconnected
/// miniatures skipped. Fixtures follow ``ScreenFixtures`` (primary
/// 1920x1080, secondaries 1600x900), the same geometry
/// ``MiniaturePanelModelTests`` documents.
@Suite struct MiniaturePanelNavigatorTests {
    private typealias Coordinate = MiniaturePanelNavigator.Coordinate

    private func makeGroup(name: String = "vertical 2-split") -> LayoutGroup {
        LayoutGroup(
            name: name,
            layouts: [
                Layout(
                    label: "Left Half",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "50%", height: "100%")
                ),
                Layout(
                    label: "Right Half",
                    position: LayoutPosition(x: "50%", y: "0"),
                    size: LayoutSize(width: "50%", height: "100%")
                ),
            ]
        )
    }

    /// Quarters in reading order: top-left, top-right, bottom-left,
    /// bottom-right (region indices 0-3).
    private func makeQuartersGroup() -> LayoutGroup {
        let quarter = LayoutSize(width: "50%", height: "50%")
        return LayoutGroup(
            name: "quarters",
            layouts: [
                Layout(label: "TL", position: LayoutPosition(x: "0", y: "0"), size: quarter),
                Layout(label: "TR", position: LayoutPosition(x: "50%", y: "0"), size: quarter),
                Layout(label: "BL", position: LayoutPosition(x: "0", y: "50%"), size: quarter),
                Layout(label: "BR", position: LayoutPosition(x: "50%", y: "50%"), size: quarter),
            ]
        )
    }

    private func makeSpace(displays: [String: LayoutGroup]) -> Space {
        Space(id: .generate(), enabled: true, displays: displays)
    }

    private func makeNavigator(
        rows: [[Space]], screens: [Screen] = ScreenFixtures.single
    ) -> MiniaturePanelNavigator {
        let collection = SpaceCollection(
            id: .generate(), name: "Test",
            rows: rows.map { SpacesRow(spaces: $0) }
        )
        return MiniaturePanelNavigator(
            model: MiniaturePanelModel.make(collection: collection, screens: screens))
    }

    // MARK: - First focus

    @Test func firstFocusIsTheTopLeftRegion() {
        let navigator = makeNavigator(rows: [[makeSpace(displays: ["0": makeGroup()])]])

        #expect(navigator.firstFocus == Coordinate(row: 0, space: 0, display: 0, region: 0))
    }

    /// The first key press only establishes focus on the top-left region,
    /// whatever direction was pressed — the GNOME `moveFocus` with no
    /// focused button.
    @Test(arguments: MiniaturePanelNavigator.Direction.allCases)
    func firstKeyPressEstablishesFocusRegardlessOfDirection(
        direction: MiniaturePanelNavigator.Direction
    ) {
        let navigator = makeNavigator(rows: [[makeSpace(displays: ["0": makeGroup()])]])

        #expect(navigator.move(from: nil, direction: direction) == navigator.firstFocus)
    }

    // MARK: - Movement within a display

    @Test func movesHorizontallyBetweenAdjacentRegions() {
        let navigator = makeNavigator(rows: [[makeSpace(displays: ["0": makeGroup()])]])
        let left = Coordinate(row: 0, space: 0, display: 0, region: 0)
        let right = Coordinate(row: 0, space: 0, display: 0, region: 1)

        #expect(navigator.move(from: left, direction: .right) == right)
        #expect(navigator.move(from: right, direction: .left) == left)
    }

    @Test func movesInAllDirectionsWithinAGrid() {
        let navigator = makeNavigator(rows: [[makeSpace(displays: ["0": makeQuartersGroup()])]])
        let topLeft = Coordinate(row: 0, space: 0, display: 0, region: 0)
        let topRight = Coordinate(row: 0, space: 0, display: 0, region: 1)
        let bottomLeft = Coordinate(row: 0, space: 0, display: 0, region: 2)
        let bottomRight = Coordinate(row: 0, space: 0, display: 0, region: 3)

        #expect(navigator.move(from: topLeft, direction: .right) == topRight)
        #expect(navigator.move(from: topLeft, direction: .down) == bottomLeft)
        #expect(navigator.move(from: bottomRight, direction: .up) == topRight)
        #expect(navigator.move(from: bottomRight, direction: .left) == bottomLeft)
    }

    // MARK: - Movement across displays, spaces, rows

    @Test func movesAcrossTheDisplaysOfASpace() {
        let navigator = makeNavigator(
            rows: [[makeSpace(displays: ["0": makeGroup(), "1": makeGroup()])]],
            screens: ScreenFixtures.secondaryRight
        )
        let rightOfPrimary = Coordinate(row: 0, space: 0, display: 0, region: 1)
        let leftOfSecondary = Coordinate(row: 0, space: 0, display: 1, region: 0)

        #expect(navigator.move(from: rightOfPrimary, direction: .right) == leftOfSecondary)
        #expect(navigator.move(from: leftOfSecondary, direction: .left) == rightOfPrimary)
    }

    @Test func movesAcrossTheSpacesOfARow() {
        let space = { self.makeSpace(displays: ["0": self.makeGroup()]) }
        let navigator = makeNavigator(rows: [[space(), space()]])
        let rightOfFirstSpace = Coordinate(row: 0, space: 0, display: 0, region: 1)
        let leftOfSecondSpace = Coordinate(row: 0, space: 1, display: 0, region: 0)

        #expect(navigator.move(from: rightOfFirstSpace, direction: .right) == leftOfSecondSpace)
        #expect(navigator.move(from: leftOfSecondSpace, direction: .left) == rightOfFirstSpace)
    }

    /// Vertical movement across rows stays in the same column: from a
    /// row's right half down to the next row's right half, not its left.
    @Test func movesAcrossRowsStayingInTheSameColumn() {
        let space = { self.makeSpace(displays: ["0": self.makeGroup()]) }
        let navigator = makeNavigator(rows: [[space()], [space()]])
        let topRight = Coordinate(row: 0, space: 0, display: 0, region: 1)
        let bottomRight = Coordinate(row: 1, space: 0, display: 0, region: 1)
        let bottomLeft = Coordinate(row: 1, space: 0, display: 0, region: 0)

        #expect(navigator.move(from: topRight, direction: .down) == bottomRight)
        #expect(navigator.move(from: bottomRight, direction: .up) == topRight)
        #expect(
            navigator.move(from: bottomLeft, direction: .up)
                == Coordinate(row: 0, space: 0, display: 0, region: 0))
    }

    // MARK: - Edges (no wrap)

    @Test func doesNotWrapAtThePanelEdges() {
        let space = { self.makeSpace(displays: ["0": self.makeGroup()]) }
        let navigator = makeNavigator(rows: [[space()], [space()]])
        let topLeft = Coordinate(row: 0, space: 0, display: 0, region: 0)
        let bottomRight = Coordinate(row: 1, space: 0, display: 0, region: 1)

        #expect(navigator.move(from: topLeft, direction: .left) == nil)
        #expect(navigator.move(from: topLeft, direction: .up) == nil)
        #expect(navigator.move(from: bottomRight, direction: .right) == nil)
        #expect(navigator.move(from: bottomRight, direction: .down) == nil)
    }

    @Test func stayingPutWhenTheCoordinateIsNotATarget() {
        let navigator = makeNavigator(rows: [[makeSpace(displays: ["0": makeGroup()])]])
        let bogus = Coordinate(row: 3, space: 0, display: 0, region: 0)

        #expect(navigator.move(from: bogus, direction: .right) == nil)
        #expect(navigator.selection(at: bogus) == nil)
    }

    // MARK: - Skipped miniatures

    /// A two-display collection on a single-screen machine renders the
    /// second display disconnected; its regions are not traversal targets,
    /// exactly as the GNOME navigator skips non-reactive buttons.
    @Test func skipsTheRegionsOfDisconnectedDisplays() {
        let navigator = makeNavigator(
            rows: [[makeSpace(displays: ["0": makeGroup(), "1": makeGroup()])]],
            screens: ScreenFixtures.single
        )
        let rightOfPrimary = Coordinate(row: 0, space: 0, display: 0, region: 1)

        #expect(navigator.move(from: rightOfPrimary, direction: .right) == nil)
        // Tab cycles only through the connected display's two regions.
        let first = navigator.advance(from: nil, reverse: false)
        let second = navigator.advance(from: first, reverse: false)
        #expect(navigator.advance(from: second, reverse: false) == first)
    }

    /// A display key the space assigns no group to renders as an empty
    /// miniature: nothing there to focus, so movement toward it finds no
    /// candidate.
    @Test func findsNothingInAnUnassignedDisplay() {
        let partial = makeSpace(displays: ["0": makeGroup()])
        let navigator = makeNavigator(
            rows: [[makeSpace(displays: ["0": makeGroup(), "1": makeGroup()]), partial]],
            screens: ScreenFixtures.secondaryRight
        )
        // The partial space's display "1" is empty; right of its display
        // "0" right half there is nothing.
        let rightmost = Coordinate(row: 0, space: 1, display: 0, region: 1)

        #expect(navigator.move(from: rightmost, direction: .right) == nil)
    }

    // MARK: - Tab order

    @Test func tabCyclesThroughAllRegionsWithWrap() {
        let space = { self.makeSpace(displays: ["0": self.makeGroup()]) }
        let navigator = makeNavigator(rows: [[space()], [space()]])
        let order = [
            Coordinate(row: 0, space: 0, display: 0, region: 0),
            Coordinate(row: 0, space: 0, display: 0, region: 1),
            Coordinate(row: 1, space: 0, display: 0, region: 0),
            Coordinate(row: 1, space: 0, display: 0, region: 1),
        ]

        #expect(navigator.advance(from: nil, reverse: false) == order[0])
        #expect(navigator.advance(from: order[0], reverse: false) == order[1])
        #expect(navigator.advance(from: order[1], reverse: false) == order[2])
        #expect(navigator.advance(from: order[3], reverse: false) == order[0])
    }

    @Test func shiftTabCyclesBackwards() {
        let navigator = makeNavigator(rows: [[makeSpace(displays: ["0": makeGroup()])]])
        let left = Coordinate(row: 0, space: 0, display: 0, region: 0)
        let right = Coordinate(row: 0, space: 0, display: 0, region: 1)

        #expect(navigator.advance(from: nil, reverse: true) == right)
        #expect(navigator.advance(from: right, reverse: true) == left)
        #expect(navigator.advance(from: left, reverse: true) == right)
    }

    /// Overlapping regions order larger-area first in the Tab order (the
    /// GNOME "parent layouts before their overlays" rule): a full-display
    /// region precedes the half it covers even when the group lists it
    /// second.
    @Test func tabOrdersLargerOverlappingRegionsFirst() {
        let group = LayoutGroup(
            name: "overlay",
            layouts: [
                Layout(
                    label: "Left Half",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "50%", height: "100%")
                ),
                Layout(
                    label: "Full",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "100%", height: "100%")
                ),
            ]
        )
        let navigator = makeNavigator(rows: [[makeSpace(displays: ["0": group])]])

        #expect(
            navigator.advance(from: nil, reverse: false)
                == Coordinate(row: 0, space: 0, display: 0, region: 1))
    }

    // MARK: - Selection

    @Test func selectionCarriesTheLayoutAndItsDisplayKey() throws {
        let navigator = makeNavigator(
            rows: [[makeSpace(displays: ["0": makeGroup(), "1": makeGroup()])]],
            screens: ScreenFixtures.secondaryRight
        )

        let event = try #require(
            navigator.selection(at: Coordinate(row: 0, space: 0, display: 1, region: 0)))
        #expect(event.layout.label == "Left Half")
        #expect(event.displayKey == "1")
    }

    // MARK: - Empty panel

    @Test func anEmptyModelHasNothingToFocus() {
        let navigator = MiniaturePanelNavigator(model: MiniaturePanelModel(rows: []))

        #expect(navigator.isEmpty)
        #expect(navigator.firstFocus == nil)
        #expect(navigator.move(from: nil, direction: .right) == nil)
        #expect(navigator.advance(from: nil, reverse: false) == nil)
    }
}
