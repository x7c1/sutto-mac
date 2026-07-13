import Foundation
import Testing

@testable import SuttoDomain

/// The settings preview model: the panel's miniature geometry with the
/// disabled spaces kept (dimmed by the view instead of filtered), each
/// space rendered with the arrangement for its own display count — the
/// GNOME preview pane's `getMonitorsForSpace`.
@Suite struct SpacePreviewModelTests {
    private func makeGroup() -> LayoutGroup {
        LayoutGroup(
            name: "vertical 2-split",
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

    private func makeSpace(displays: [String: LayoutGroup], enabled: Bool = true) -> Space {
        Space(id: .generate(), enabled: enabled, displays: displays)
    }

    private func makeCollection(rows: [SpacesRow]) -> SpaceCollection {
        SpaceCollection(id: .generate(), name: "Test", rows: rows)
    }

    // MARK: - Disabled spaces

    /// Unlike the panel model, disabled spaces stay in the preview — the
    /// user must see (and click) them to re-enable.
    @Test func keepsDisabledSpacesWithTheirFlag() throws {
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [
                makeSpace(displays: ["0": makeGroup()]),
                makeSpace(displays: ["0": makeGroup()], enabled: false),
            ])
        ])

        let model = SpacePreviewModel.make(collection: collection, screens: ScreenFixtures.single)

        #expect(model.collectionId == collection.id)
        #expect(model.rows.count == 1)
        #expect(model.rows[0].spaces.map(\.enabled) == [true, false])
    }

    /// A collection with every space disabled still previews every space —
    /// the state the GNOME preferences leave you in after clicking them
    /// all off (the panel side then renders empty).
    @Test func keepsARowOfOnlyDisabledSpaces() {
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [makeSpace(displays: ["0": makeGroup()], enabled: false)])
        ])

        let model = SpacePreviewModel.make(collection: collection, screens: ScreenFixtures.single)

        #expect(model.rows.count == 1)
        #expect(model.rows[0].spaces.map(\.enabled) == [false])
    }

    /// Rows with no spaces at all are dropped, like the GNOME preview's
    /// `updatePreview` skipping empty rows.
    @Test func dropsRowsWithoutSpaces() {
        let collection = makeCollection(rows: [
            SpacesRow(spaces: []),
            SpacesRow(spaces: [makeSpace(displays: ["0": makeGroup()])]),
        ])

        let model = SpacePreviewModel.make(collection: collection, screens: ScreenFixtures.single)

        #expect(model.rows.count == 1)
    }

    @Test func previewsAnEmptyCollectionAsNoRows() {
        let model = SpacePreviewModel.make(
            collection: makeCollection(rows: []), screens: ScreenFixtures.single)

        #expect(model.rows.isEmpty)
    }

    // MARK: - Shared geometry

    /// A fully enabled collection previews with exactly the miniatures the
    /// panel renders — same math, same frames — so the two surfaces can
    /// never drift apart.
    @Test func matchesThePanelGeometryForEnabledSpaces() {
        let preset = PresetGenerator.generate(monitorCount: 2, monitorType: .standard)

        let preview = SpacePreviewModel.make(
            collection: preset, screens: ScreenFixtures.secondaryRight)
        let panel = MiniaturePanelModel.make(
            collection: preset, screens: ScreenFixtures.secondaryRight)

        #expect(preview.rows.map { $0.spaces.map(\.miniature) } == panel.rows.map(\.spaces))
    }

    /// Each space renders with the arrangement for its own display count
    /// (the GNOME `getMonitorsForSpace`): a single-display space in a
    /// collection that also holds a two-display space previews with one
    /// display, not the collection-wide two.
    @Test func resolvesTheArrangementPerSpace() throws {
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [
                makeSpace(displays: ["0": makeGroup(), "1": makeGroup()]),
                makeSpace(displays: ["0": makeGroup()]),
            ])
        ])

        let model = SpacePreviewModel.make(
            collection: collection, screens: ScreenFixtures.secondaryRight)

        let spaces = try #require(model.rows.first?.spaces)
        #expect(spaces[0].miniature.displays.map(\.key) == ["0", "1"])
        #expect(spaces[1].miniature.displays.map(\.key) == ["0"])
        // The single-display miniature is narrower: no second display.
        #expect(spaces[1].miniature.width < spaces[0].miniature.width)
    }

    /// Stored monitor environments feed the preview exactly as they feed
    /// the panel: a two-display space on a one-screen machine renders with
    /// the remembered geometry, its detached display marked disconnected.
    @Test func consultsStoredEnvironmentsForDetachedDisplays() throws {
        let remembered = MonitorEnvironment(
            id: MonitorEnvironmentId.generate(for: MonitorFixtures.laptopWithUltrawide),
            monitors: MonitorFixtures.laptopWithUltrawide,
            lastActiveCollectionId: nil,
            lastActiveAt: Date(timeIntervalSince1970: 0)
        )
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [makeSpace(displays: ["0": makeGroup(), "1": makeGroup()])])
        ])

        let model = SpacePreviewModel.make(
            collection: collection, screens: ScreenFixtures.single,
            environments: [remembered])

        let displays = try #require(model.rows.first?.spaces.first?.miniature.displays)
        #expect(displays.map(\.isConnected) == [true, false])
    }
}
