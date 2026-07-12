import Testing

@testable import SuttoDomain

/// Tests for `extractLayoutIds(from:)`, the port of
/// `domain/layout/extract-layout-ids.ts` (which has no unit tests in the
/// GNOME version). The TypeScript original returns a `ValueSet` keyed by
/// `toString()`; these tests pin that the Swift `Set<LayoutId>` keeps the
/// same semantics: every layout across the whole hierarchy is visited, and
/// ids that stringify identically count once.
@Suite struct ExtractLayoutIdsTests {
    private static func makeLayout(id: String) throws -> Layout {
        Layout(
            id: try LayoutId(id),
            hash: generateLayoutHash(x: "0", y: "0", width: "50%", height: "100%"),
            label: "Left Half",
            position: LayoutPosition(x: "0", y: "0"),
            size: LayoutSize(width: "50%", height: "100%")
        )
    }

    private static func makeCollection(rows: [SpacesRow]) throws -> SpaceCollection {
        SpaceCollection(
            id: try CollectionId("550e8400-e29b-41d4-a716-446655440000"),
            name: "Work",
            rows: rows
        )
    }

    @Test func returnsEmptySetForNoCollections() {
        #expect(extractLayoutIds(from: []).isEmpty)
    }

    @Test func collectsIdsAcrossRowsSpacesAndDisplays() throws {
        let idA = "00000000-0000-4000-8000-00000000000a"
        let idB = "00000000-0000-4000-8000-00000000000b"
        let idC = "00000000-0000-4000-8000-00000000000c"
        let collection = try Self.makeCollection(rows: [
            SpacesRow(spaces: [
                Space(
                    id: SpaceId.generate(),
                    enabled: true,
                    displays: [
                        "0": LayoutGroup(name: "left", layouts: [try Self.makeLayout(id: idA)]),
                        "1": LayoutGroup(name: "right", layouts: [try Self.makeLayout(id: idB)]),
                    ]
                )
            ]),
            SpacesRow(spaces: [
                Space(
                    id: SpaceId.generate(),
                    enabled: false,
                    displays: [
                        "0": LayoutGroup(name: "full", layouts: [try Self.makeLayout(id: idC)])
                    ]
                )
            ]),
        ])

        let ids = extractLayoutIds(from: [collection])
        #expect(ids == Set([try LayoutId(idA), try LayoutId(idB), try LayoutId(idC)]))
    }

    @Test func deduplicatesIdsThatStringifyIdentically() throws {
        let shared = "00000000-0000-4000-8000-000000000001"
        let collection = try Self.makeCollection(rows: [
            SpacesRow(spaces: [
                Space(
                    id: SpaceId.generate(),
                    enabled: true,
                    displays: [
                        "0": LayoutGroup(
                            name: "duplicated",
                            layouts: [
                                try Self.makeLayout(id: shared),
                                try Self.makeLayout(id: shared.uppercased()),
                            ]
                        )
                    ]
                )
            ])
        ])

        let ids = extractLayoutIds(from: [collection])
        #expect(ids.count == 1)
    }

    @Test func spansMultipleCollections() throws {
        let idA = "00000000-0000-4000-8000-00000000000a"
        let idB = "00000000-0000-4000-8000-00000000000b"
        let first = try Self.makeCollection(rows: [
            SpacesRow(spaces: [
                Space(
                    id: SpaceId.generate(),
                    enabled: true,
                    displays: ["0": LayoutGroup(name: "a", layouts: [try Self.makeLayout(id: idA)])]
                )
            ])
        ])
        let second = try Self.makeCollection(rows: [
            SpacesRow(spaces: [
                Space(
                    id: SpaceId.generate(),
                    enabled: true,
                    displays: ["0": LayoutGroup(name: "b", layouts: [try Self.makeLayout(id: idB)])]
                )
            ])
        ])

        let ids = extractLayoutIds(from: [first, second])
        #expect(ids == Set([try LayoutId(idA), try LayoutId(idB)]))
    }
}
