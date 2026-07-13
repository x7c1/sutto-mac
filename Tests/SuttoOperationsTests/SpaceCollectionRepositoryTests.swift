import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

/// The repository extension shared by every implementation: the per-space
/// enabled update (the GNOME `updateSpaceEnabled`, presets searched before
/// customs) exercised over the in-memory stub.
@Suite @MainActor struct SpaceCollectionRepositoryTests {
    private let repository = InMemorySpaceCollectionRepository()

    private func makeCollection(name: String) -> SpaceCollection {
        SpaceCollection(
            id: .generate(), name: name,
            rows: [SpacesRow(spaces: [Space(id: .generate(), enabled: true, displays: [:])])]
        )
    }

    @Test func updatesAPresetSpaceInThePresetDocument() throws {
        let preset = makeCollection(name: "Preset")
        repository.presetCollections = [preset]
        let spaceId = preset.rows[0].spaces[0].id

        let updated = try repository.updateSpaceEnabled(
            collectionId: preset.id, spaceId: spaceId, enabled: false)

        #expect(updated)
        #expect(repository.presetCollections[0].space(withId: spaceId)?.enabled == false)
    }

    @Test func updatesACustomSpaceInTheCustomDocument() throws {
        let preset = makeCollection(name: "Preset")
        let custom = makeCollection(name: "Custom")
        repository.presetCollections = [preset]
        repository.collections = [custom]
        let spaceId = custom.rows[0].spaces[0].id

        let updated = try repository.updateSpaceEnabled(
            collectionId: custom.id, spaceId: spaceId, enabled: false)

        #expect(updated)
        #expect(repository.collections[0].space(withId: spaceId)?.enabled == false)
        #expect(repository.presetCollections == [preset])
    }

    /// A space id that exists nowhere reports `false` and writes nothing —
    /// the GNOME method's not-found path.
    @Test func reportsFalseWhenTheSpaceIsNowhere() throws {
        let preset = makeCollection(name: "Preset")
        repository.presetCollections = [preset]

        let updated = try repository.updateSpaceEnabled(
            collectionId: preset.id, spaceId: .generate(), enabled: false)

        #expect(!updated)
        #expect(repository.presetCollections == [preset])
    }
}
