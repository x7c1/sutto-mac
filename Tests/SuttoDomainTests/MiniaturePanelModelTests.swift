import Testing

@testable import SuttoDomain

/// Fixtures and hand-computed expectations follow ``ScreenFixtures``:
/// primary 1920x1080, secondaries 1600x900. The scale for any space
/// containing the primary is `100/1080` (the height limit wins:
/// `min(240/1920, 100/1080)`), so the primary miniature is
/// `1920 * 100/1080 - 6 = 171.78` by `100 - 6 = 94` points, offset by the
/// 6-point margin.
@Suite struct MiniaturePanelModelTests {
    private let primaryScale = 100.0 / 1080.0

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

    private func makeCollection(spaces: [Space]) -> SpaceCollection {
        SpaceCollection(
            id: .generate(), name: "Test", rows: [SpacesRow(spaces: spaces)]
        )
    }

    private func makeSpace(displays: [String: LayoutGroup], enabled: Bool = true) -> Space {
        Space(id: .generate(), enabled: enabled, displays: displays)
    }

    private func approximately(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.001
    }

    // MARK: - Single display

    @Test func scalesTheRealScreenGeometryIntoTheMiniature() throws {
        let collection = makeCollection(spaces: [makeSpace(displays: ["0": makeGroup()])])

        let model = MiniaturePanelModel.make(collection: collection, screens: ScreenFixtures.single)

        let space = try #require(model.rows.first?.spaces.first)
        let display = try #require(space.displays.first)
        #expect(display.key == "0")
        #expect(display.isPrimary)
        #expect(display.isConnected)
        #expect(approximately(display.frame.x, 6))
        #expect(approximately(display.frame.y, 6))
        #expect(approximately(display.frame.width, 1920 * primaryScale - 6))
        #expect(approximately(display.frame.height, 94))
        // Container wraps the display with the margin on every side.
        #expect(approximately(space.width, display.frame.maxX + 6))
        #expect(approximately(space.height, display.frame.maxY + 6))
    }

    @Test func regionsAreProportionalToTheirLayouts() throws {
        let collection = makeCollection(spaces: [makeSpace(displays: ["0": makeGroup()])])

        let model = MiniaturePanelModel.make(collection: collection, screens: ScreenFixtures.single)

        let display = try #require(model.rows.first?.spaces.first?.displays.first)
        let left = try #require(display.regions.first)
        let right = try #require(display.regions.last)
        // 50% of the 171.78-point display; the evaluator rounds like
        // JavaScript's Math.round: 85.89 → 86.
        #expect(left.frame == PixelRect(x: 0, y: 0, width: 86, height: 94))
        #expect(right.frame == PixelRect(x: 86, y: 0, width: 86, height: 94))
        #expect(left.layout.label == "Left Half")
        #expect(right.layout.label == "Right Half")
    }

    /// Absolute pixel expressions shrink with the miniature: 960px on a
    /// 1920-point-wide work area is half the display, the same as "50%".
    @Test func scalesPixelExpressionsAgainstTheWorkArea() throws {
        let group = LayoutGroup(
            name: "pixels",
            layouts: [
                Layout(
                    label: "Fixed Half",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "960px", height: "100%")
                )
            ]
        )
        let collection = makeCollection(spaces: [makeSpace(displays: ["0": group])])

        let model = MiniaturePanelModel.make(collection: collection, screens: ScreenFixtures.single)

        let region = try #require(model.rows.first?.spaces.first?.displays.first?.regions.first)
        #expect(region.frame.width == 86)
    }

    // MARK: - Preset shapes

    @Test func rendersTheSingleMonitorStandardPresetTwoSpacesPerRow() {
        let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)

        let model = MiniaturePanelModel.make(collection: preset, screens: ScreenFixtures.single)

        #expect(model.rows.count == preset.rows.count)
        let spaces = model.rows.flatMap(\.spaces)
        #expect(spaces.count == PresetConfiguration.standardLayoutGroupNames.count)
        #expect(model.rows.allSatisfy { $0.spaces.count <= 2 })
        #expect(spaces.allSatisfy { $0.displays.count == 1 })
    }

    /// The wide preset's widest group renders as one region per layout,
    /// each proportional and inside the display — the shape that replaces
    /// v0.2's unreadable flat list of text buttons.
    @Test func rendersWidePresetGroupsAsProportionalRegions() {
        let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .wide)
        let wideScreen = Screen(
            frame: PixelRect(x: 0, y: 0, width: 3440, height: 1440),
            visibleFrame: PixelRect(x: 0, y: 0, width: 3440, height: 1415)
        )

        let model = MiniaturePanelModel.make(collection: preset, screens: [wideScreen])

        let spaces = model.rows.flatMap(\.spaces)
        let groups = preset.rows.flatMap(\.spaces).map { $0.displays["0"]! }
        #expect(spaces.count == groups.count)
        for (space, group) in zip(spaces, groups) {
            let display = space.displays[0]
            #expect(display.regions.count == group.layouts.count)
            for region in display.regions {
                #expect(region.frame.x >= 0)
                #expect(region.frame.y >= 0)
                // Rounding may overshoot by at most a point.
                #expect(region.frame.maxX <= display.frame.width + 1)
                #expect(region.frame.maxY <= display.frame.height + 1)
            }
        }
    }

    // MARK: - Multi-display arrangement

    @Test func arrangesASecondaryToTheRightAfterThePrimary() throws {
        let preset = PresetGenerator.generate(monitorCount: 2, monitorType: .standard)

        let model = MiniaturePanelModel.make(
            collection: preset, screens: ScreenFixtures.secondaryRight)

        let space = try #require(model.rows.first?.spaces.first)
        #expect(space.displays.map(\.key) == ["0", "1"])
        let primary = space.displays[0]
        let secondary = space.displays[1]
        #expect(primary.isPrimary)
        #expect(!secondary.isPrimary)
        #expect(secondary.isConnected)
        // To the right, with the margin gap between them.
        #expect(approximately(secondary.frame.x, 1920 * primaryScale + 6))
        // Bottom edges aligned in AppKit means the smaller secondary sits
        // lower in the top-left-origin miniature.
        #expect(approximately(secondary.frame.y, 180 * primaryScale + 6))
        #expect(approximately(secondary.frame.width, 1600 * primaryScale - 6))
        #expect(approximately(secondary.frame.height, 900 * primaryScale - 6))
        // Both displays share the space's scale: relative sizes faithful.
        #expect(secondary.frame.width < primary.frame.width)
    }

    @Test func arrangesAStackedSecondaryAboveThePrimary() throws {
        let preset = PresetGenerator.generate(monitorCount: 2, monitorType: .standard)

        let model = MiniaturePanelModel.make(
            collection: preset, screens: ScreenFixtures.stackedAbove)

        let space = try #require(model.rows.first?.spaces.first)
        let primary = space.displays[0]
        let secondary = space.displays[1]
        // AppKit y grows upward; the miniature's top-left space puts the
        // screen stacked above at a smaller y.
        #expect(secondary.frame.maxY < primary.frame.y)
        #expect(approximately(secondary.frame.y, 6))
        #expect(approximately(primary.frame.y, 900 * primaryScale + 6))
    }

    @Test func arrangesASecondaryWithNegativeCoordinates() throws {
        let preset = PresetGenerator.generate(monitorCount: 2, monitorType: .standard)

        let model = MiniaturePanelModel.make(
            collection: preset, screens: ScreenFixtures.belowAndLeft)

        let space = try #require(model.rows.first?.spaces.first)
        let primary = space.displays[0]
        let secondary = space.displays[1]
        // Below and left of the primary: smaller x, larger y.
        #expect(secondary.frame.x < primary.frame.x)
        #expect(secondary.frame.y > primary.frame.maxY)
        #expect(approximately(secondary.frame.x, 6))
        #expect(approximately(primary.frame.x, 1600 * primaryScale + 6))
    }

    @Test(arguments: [
        ScreenFixtures.secondaryRight,
        ScreenFixtures.secondaryLeft,
        ScreenFixtures.stackedAbove,
        ScreenFixtures.stackedBelow,
        ScreenFixtures.belowAndLeft,
    ])
    func everyArrangementRespectsTheMiniatureLimits(screens: [Screen]) {
        let preset = PresetGenerator.generate(monitorCount: 2, monitorType: .standard)

        let model = MiniaturePanelModel.make(collection: preset, screens: screens)

        for space in model.rows.flatMap(\.spaces) {
            for display in space.displays {
                #expect(display.frame.width <= MiniaturePanelModel.Metrics.maxDisplayWidth)
                #expect(display.frame.height <= MiniaturePanelModel.Metrics.maxDisplayHeight)
                // Every display sits inside the container, margin included.
                #expect(display.frame.x >= MiniaturePanelModel.Metrics.displayMargin - 0.001)
                #expect(display.frame.y >= MiniaturePanelModel.Metrics.displayMargin - 0.001)
                #expect(display.frame.maxX <= space.width + 0.001)
                #expect(display.frame.maxY <= space.height + 0.001)
            }
        }
    }

    // MARK: - Count mismatches (GNOME getMonitorsForRendering fallback)

    /// A collection made for two displays on a single-screen machine:
    /// the arrangement is synthesized side by side from the primary's
    /// size, and the second display renders disconnected (grayed out,
    /// non-clickable).
    @Test func synthesizesDisconnectedDisplaysWhenTheCollectionExceedsTheScreens() throws {
        let preset = PresetGenerator.generate(monitorCount: 2, monitorType: .standard)

        let model = MiniaturePanelModel.make(collection: preset, screens: ScreenFixtures.single)

        let space = try #require(model.rows.first?.spaces.first)
        #expect(space.displays.map(\.key) == ["0", "1"])
        let first = space.displays[0]
        let second = space.displays[1]
        #expect(first.isConnected)
        #expect(!second.isConnected)
        // Synthesized displays clone the primary's size, side by side.
        #expect(approximately(second.frame.width, first.frame.width))
        #expect(approximately(second.frame.height, first.frame.height))
        #expect(approximately(second.frame.x, first.frame.maxX + 6))
        #expect(approximately(second.frame.y, first.frame.y))
        // Both still carry their regions.
        #expect(!second.regions.isEmpty)
    }

    /// A single-display collection on a two-screen machine renders one
    /// display per space (the collection knows nothing about the second
    /// screen), synthesized from the primary's size.
    @Test func rendersOnlyTheCollectionsDisplaysWhenScreensExceedIt() throws {
        let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)

        let model = MiniaturePanelModel.make(
            collection: preset, screens: ScreenFixtures.secondaryRight)

        let space = try #require(model.rows.first?.spaces.first)
        #expect(space.displays.map(\.key) == ["0"])
        #expect(space.displays[0].isConnected)
    }

    @Test func fallsBackToDefaultGeometryWithoutScreens() throws {
        let collection = makeCollection(spaces: [makeSpace(displays: ["0": makeGroup()])])

        let model = MiniaturePanelModel.make(collection: collection, screens: [])

        let display = try #require(model.rows.first?.spaces.first?.displays.first)
        #expect(!display.isConnected)
        // 1920x1080 fallback scaled by 100/1080, like the real primary.
        #expect(approximately(display.frame.width, 1920 * primaryScale - 6))
        #expect(approximately(display.frame.height, 94))
    }

    // MARK: - Space content

    /// A display key the space assigns no group to still renders — as an
    /// empty miniature — so every space shows the full arrangement.
    @Test func rendersAnEmptyMiniatureForAnUnassignedDisplayKey() throws {
        let assigned = makeSpace(displays: ["0": makeGroup(), "1": makeGroup()])
        let partial = makeSpace(displays: ["0": makeGroup()])
        let collection = makeCollection(spaces: [assigned, partial])

        let model = MiniaturePanelModel.make(
            collection: collection, screens: ScreenFixtures.secondaryRight)

        let partialSpace = try #require(model.rows.first?.spaces.last)
        #expect(partialSpace.displays.map(\.key) == ["0", "1"])
        #expect(!partialSpace.displays[0].regions.isEmpty)
        #expect(partialSpace.displays[1].regions.isEmpty)
    }

    @Test func filtersDisabledSpacesAndDropsEmptiedRows() {
        let collection = SpaceCollection(
            id: .generate(),
            name: "Test",
            rows: [
                SpacesRow(spaces: [
                    makeSpace(displays: ["0": makeGroup()], enabled: false),
                    makeSpace(displays: ["0": makeGroup()]),
                ]),
                SpacesRow(spaces: [
                    makeSpace(displays: ["0": makeGroup()], enabled: false)
                ]),
            ]
        )

        let model = MiniaturePanelModel.make(collection: collection, screens: ScreenFixtures.single)

        #expect(model.rows.count == 1)
        #expect(model.rows[0].spaces.count == 1)
    }

    @Test func rendersEmptyWhenEverySpaceIsDisabled() {
        let collection = makeCollection(spaces: [
            makeSpace(displays: ["0": makeGroup()], enabled: false)
        ])

        let model = MiniaturePanelModel.make(collection: collection, screens: ScreenFixtures.single)

        #expect(model.rows.isEmpty)
    }

    /// One malformed expression drops that layout, not the panel: the
    /// remaining regions still render.
    @Test func skipsLayoutsWithInvalidExpressions() throws {
        let group = LayoutGroup(
            name: "half broken",
            layouts: [
                Layout(
                    label: "Broken",
                    position: LayoutPosition(x: "nonsense", y: "0"),
                    size: LayoutSize(width: "50%", height: "100%")
                ),
                Layout(
                    label: "Fine",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "50%", height: "100%")
                ),
            ]
        )
        let collection = makeCollection(spaces: [makeSpace(displays: ["0": group])])

        let model = MiniaturePanelModel.make(collection: collection, screens: ScreenFixtures.single)

        let display = try #require(model.rows.first?.spaces.first?.displays.first)
        #expect(display.regions.map(\.layout.label) == ["Fine"])
    }
}
