import Testing

@testable import SuttoDomain

/// Pins the v0.2 panel projection rule: one layout group per enabled space
/// in reading order, taking each space's primary-display (`"0"`) group.
/// See `LayoutPanelProjection` for the GNOME evidence behind the rule.
@Suite struct LayoutPanelProjectionTests {
    private func makeGroup(name: String) -> LayoutGroup {
        LayoutGroup(
            name: name,
            layouts: [
                Layout(
                    label: "\(name) layout",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "50%", height: "100%")
                )
            ]
        )
    }

    private func makeSpace(enabled: Bool = true, displays: [String: LayoutGroup]) -> Space {
        Space(id: .generate(), enabled: enabled, displays: displays)
    }

    private func makeCollection(rows: [SpacesRow]) -> SpaceCollection {
        SpaceCollection(id: .generate(), name: "Test", rows: rows)
    }

    @Test func projectsOneGroupPerSpaceInReadingOrder() {
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [
                makeSpace(displays: ["0": makeGroup(name: "first")]),
                makeSpace(displays: ["0": makeGroup(name: "second")]),
            ]),
            SpacesRow(spaces: [
                makeSpace(displays: ["0": makeGroup(name: "third")])
            ]),
        ])

        let groups = LayoutPanelProjection.layoutGroups(in: collection)

        #expect(groups.map(\.name) == ["first", "second", "third"])
    }

    /// Disabled spaces do not appear, mirroring `filterEnabledSpaces` in
    /// the GNOME `ui/main-panel/index.ts`.
    @Test func skipsDisabledSpaces() {
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [
                makeSpace(displays: ["0": makeGroup(name: "shown")]),
                makeSpace(enabled: false, displays: ["0": makeGroup(name: "hidden")]),
            ])
        ])

        let groups = LayoutPanelProjection.layoutGroups(in: collection)

        #expect(groups.map(\.name) == ["shown"])
    }

    /// A space assigned only to other monitors contributes nothing,
    /// mirroring how the GNOME miniature view skips monitors that do not
    /// exist (only monitor "0" exists on the v0.2 single-display panel).
    @Test func skipsSpacesWithoutAPrimaryDisplayAssignment() {
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [
                makeSpace(displays: ["1": makeGroup(name: "secondary only")]),
                makeSpace(displays: ["0": makeGroup(name: "primary")]),
            ])
        ])

        let groups = LayoutPanelProjection.layoutGroups(in: collection)

        #expect(groups.map(\.name) == ["primary"])
    }

    /// A space spanning several monitors contributes only its primary
    /// group.
    @Test func usesOnlyThePrimaryDisplayOfAMultiMonitorSpace() {
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [
                makeSpace(displays: [
                    "0": makeGroup(name: "primary"),
                    "1": makeGroup(name: "secondary"),
                ])
            ])
        ])

        let groups = LayoutPanelProjection.layoutGroups(in: collection)

        #expect(groups.map(\.name) == ["primary"])
    }

    @Test func emptyCollectionProjectsToNothing() {
        let collection = makeCollection(rows: [])

        #expect(LayoutPanelProjection.layoutGroups(in: collection).isEmpty)
    }

    /// All spaces disabled yields an empty panel, like the GNOME panel
    /// after filtering — deliberately not a fallback to presets.
    @Test func allSpacesDisabledProjectsToNothing() {
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [
                makeSpace(enabled: false, displays: ["0": makeGroup(name: "hidden")])
            ])
        ])

        #expect(LayoutPanelProjection.layoutGroups(in: collection).isEmpty)
    }
}
