import Foundation
import Testing

@testable import SuttoDomain

/// The per-space enabled update on a collection — the pure half of the
/// GNOME repository's `updateSpaceEnabled`.
@Suite struct SpaceCollectionTests {
    private func makeSpace(enabled: Bool = true) -> Space {
        Space(id: .generate(), enabled: enabled, displays: [:])
    }

    private func makeCollection(rows: [SpacesRow]) -> SpaceCollection {
        SpaceCollection(id: .generate(), name: "Test", rows: rows)
    }

    @Test func updatingSetsExactlyTheTargetSpacesFlag() throws {
        let target = makeSpace()
        let other = makeSpace()
        let collection = makeCollection(rows: [
            SpacesRow(spaces: [other]),
            SpacesRow(spaces: [target]),
        ])

        let updated = try #require(collection.updatingSpace(target.id, enabled: false))

        #expect(updated.space(withId: target.id)?.enabled == false)
        #expect(updated.space(withId: other.id)?.enabled == true)
        // Identity and structure are untouched.
        #expect(updated.id == collection.id)
        #expect(updated.name == collection.name)
        #expect(updated.rows.map { $0.spaces.map(\.id) } == collection.rows.map { $0.spaces.map(\.id) })
    }

    @Test func updatingAnUnknownSpaceReturnsNil() {
        let collection = makeCollection(rows: [SpacesRow(spaces: [makeSpace()])])

        #expect(collection.updatingSpace(.generate(), enabled: false) == nil)
    }

    /// No last-enabled-space guard: disabling the only enabled space is a
    /// valid update, like the GNOME preferences (the panel then renders
    /// empty).
    @Test func theLastEnabledSpaceCanBeDisabled() throws {
        let only = makeSpace()
        let collection = makeCollection(rows: [SpacesRow(spaces: [only])])

        let updated = try #require(collection.updatingSpace(only.id, enabled: false))

        #expect(updated.rows.flatMap(\.spaces).allSatisfy { !$0.enabled })
    }

    @Test func reenablingADisabledSpaceRestoresIt() throws {
        let space = makeSpace(enabled: false)
        let collection = makeCollection(rows: [SpacesRow(spaces: [space])])

        let updated = try #require(collection.updatingSpace(space.id, enabled: true))

        #expect(updated.space(withId: space.id)?.enabled == true)
    }
}
