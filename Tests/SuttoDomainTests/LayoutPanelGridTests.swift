import Testing

@testable import SuttoDomain

@Suite struct LayoutPanelGridTests {
    @Test func buildsOneRowPerGroupInDeclarationOrder() {
        let grid = LayoutPanelGrid(groups: BuiltInPresets.standardLayoutGroups)

        #expect(
            grid.rows.map(\.groupName) == [
                "vertical 2-split",
                "horizontal 2-split",
                "vertical 3-split",
                "full screen",
            ])
    }

    @Test func rowsKeepTheLayoutsOfTheirGroupInOrder() {
        let grid = LayoutPanelGrid(groups: BuiltInPresets.standardLayoutGroups)

        #expect(
            grid.rows.map { $0.layouts.map(\.label) } == [
                ["Left Half", "Right Half"],
                ["Top Half", "Bottom Half"],
                ["Left Third", "Center Third", "Right Third"],
                ["full"],
            ])
    }

    @Test func skipsGroupsWithoutLayouts() {
        let groups = [
            LayoutGroup(name: "empty", layouts: []),
            LayoutGroup(
                name: "solo",
                layouts: [
                    Layout(
                        label: "full",
                        position: LayoutPosition(x: "0", y: "0"),
                        size: LayoutSize(width: "100%", height: "100%")
                    )
                ]
            ),
        ]

        let grid = LayoutPanelGrid(groups: groups)

        #expect(grid.rows.map(\.groupName) == ["solo"])
    }

    @Test func isEmptyForNoGroups() {
        #expect(LayoutPanelGrid(groups: []).rows.isEmpty)
    }
}
