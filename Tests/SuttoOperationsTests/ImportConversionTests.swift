import SuttoDomain
import Testing

@testable import SuttoOperations

/// Tests for the configuration → rows conversion, ported from the behavior
/// of `configurationToSpacesRows` / `settingToSpace` / `settingToLayout` in
/// the GNOME `import-collection.ts` (which ships no tests of its own).
@Suite struct ImportConversionTests {
    private let halfSplit = LayoutGroupSetting(
        name: "half split",
        layouts: [
            LayoutSetting(label: "Left", x: "0", y: "0", width: "50%", height: "100%"),
            LayoutSetting(label: "Right", x: "50%", y: "0", width: "50%", height: "100%"),
        ]
    )
    private let full = LayoutGroupSetting(
        name: "full",
        layouts: [
            LayoutSetting(label: "Full", x: "0", y: "0", width: "100%", height: "100%")
        ]
    )

    @Test func preservesTheRowAndSpaceStructure() {
        let configuration = LayoutConfiguration(
            name: "Test",
            layoutGroups: [halfSplit, full],
            rows: [
                SpacesRowSetting(spaces: [
                    SpaceSetting(displays: ["0": "half split"]),
                    SpaceSetting(displays: ["0": "full"]),
                ]),
                SpacesRowSetting(spaces: [
                    SpaceSetting(displays: ["0": "full"])
                ]),
            ]
        )

        let rows = ImportConversion.spacesRows(from: configuration)

        #expect(rows.count == 2)
        #expect(rows[0].spaces.count == 2)
        #expect(rows[1].spaces.count == 1)
        #expect(rows[0].spaces[0].displays["0"]?.name == "half split")
        #expect(rows[0].spaces[1].displays["0"]?.name == "full")
        #expect(rows[1].spaces[0].displays["0"]?.name == "full")
    }

    /// Imported spaces start enabled, like `settingToSpace` hardcoding
    /// `enabled: true`.
    @Test func importedSpacesStartEnabled() {
        let configuration = LayoutConfiguration(
            name: "Test",
            layoutGroups: [full],
            rows: [SpacesRowSetting(spaces: [SpaceSetting(displays: ["0": "full"])])]
        )

        let rows = ImportConversion.spacesRows(from: configuration)

        #expect(rows[0].spaces[0].enabled)
    }

    @Test func copiesLayoutGeometryVerbatim() throws {
        let configuration = LayoutConfiguration(
            name: "Test",
            layoutGroups: [halfSplit],
            rows: [SpacesRowSetting(spaces: [SpaceSetting(displays: ["0": "half split"])])]
        )

        let rows = ImportConversion.spacesRows(from: configuration)
        let layouts = try #require(rows[0].spaces[0].displays["0"]).layouts

        #expect(layouts.map(\.label) == ["Left", "Right"])
        #expect(layouts[0].position == LayoutPosition(x: "0", y: "0"))
        #expect(layouts[0].size == LayoutSize(width: "50%", height: "100%"))
        #expect(layouts[1].position == LayoutPosition(x: "50%", y: "0"))
        #expect(layouts[1].size == LayoutSize(width: "50%", height: "100%"))
    }

    /// The hash is minted from the coordinate expressions with the shared
    /// algorithm, like `settingToLayout` calling `generateLayoutHash`.
    @Test func mintsTheCoordinateHashPerLayout() throws {
        let configuration = LayoutConfiguration(
            name: "Test",
            layoutGroups: [halfSplit],
            rows: [SpacesRowSetting(spaces: [SpaceSetting(displays: ["0": "half split"])])]
        )

        let rows = ImportConversion.spacesRows(from: configuration)
        let layouts = try #require(rows[0].spaces[0].displays["0"]).layouts

        #expect(layouts[0].hash == generateLayoutHash(x: "0", y: "0", width: "50%", height: "100%"))
        #expect(
            layouts[1].hash == generateLayoutHash(x: "50%", y: "0", width: "50%", height: "100%"))
    }

    /// Every conversion mints fresh ids — two spaces referencing the same
    /// group setting get distinct layout ids, exactly like the GNOME
    /// importer resolving each display independently through
    /// `settingToLayout`'s `uuidGenerator.generate()`.
    @Test func mintsFreshIdsPerReference() {
        let configuration = LayoutConfiguration(
            name: "Test",
            layoutGroups: [full],
            rows: [
                SpacesRowSetting(spaces: [
                    SpaceSetting(displays: ["0": "full", "1": "full"]),
                    SpaceSetting(displays: ["0": "full"]),
                ])
            ]
        )

        let rows = ImportConversion.spacesRows(from: configuration)

        let spaceIds = rows.flatMap(\.spaces).map(\.id)
        #expect(Set(spaceIds).count == spaceIds.count)

        let layoutIds = extractLayoutIds(from: [
            SpaceCollection(id: .generate(), name: "Test", rows: rows)
        ])
        #expect(layoutIds.count == 3)
    }

    /// A display referencing an unknown group is skipped with a warning,
    /// mirroring the GNOME importer's log-and-continue.
    @Test func skipsUnresolvableGroupReferencesWithAWarning() throws {
        let configuration = LayoutConfiguration(
            name: "Test",
            layoutGroups: [full],
            rows: [
                SpacesRowSetting(spaces: [
                    SpaceSetting(displays: ["0": "no such group", "1": "full"])
                ])
            ]
        )

        var warnings: [String] = []
        let rows = ImportConversion.spacesRows(from: configuration) { warnings.append($0) }

        let space = try #require(rows.first?.spaces.first)
        #expect(space.displays.keys.sorted() == ["1"])
        #expect(warnings == ["Layout Group \"no such group\" not found for monitor 0"])
    }
}
