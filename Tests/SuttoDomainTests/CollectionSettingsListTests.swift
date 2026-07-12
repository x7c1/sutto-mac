import Testing

@testable import SuttoDomain

@Suite struct CollectionSettingsListTests {
    private func makeCollection(name: String) -> SpaceCollection {
        SpaceCollection(id: .generate(), name: name, rows: [])
    }

    @Test func withNothingImportedTheListIsJustActivePresets() {
        let entries = CollectionSettingsList.entries(customCollections: [], activeId: nil)

        #expect(
            entries == [
                CollectionSettingsEntry(kind: .presets, name: "Presets", isActive: true)
            ])
    }

    @Test func listsPresetsFirstThenCustomsInStoredOrder() {
        let work = makeCollection(name: "Work")
        let home = makeCollection(name: "Home")

        let entries = CollectionSettingsList.entries(
            customCollections: [work, home], activeId: nil)

        #expect(entries.map(\.name) == ["Presets", "Work", "Home"])
        #expect(entries.map(\.kind) == [.presets, .custom(work.id), .custom(home.id)])
    }

    @Test func marksTheStoredCustomCollectionActive() {
        let work = makeCollection(name: "Work")
        let home = makeCollection(name: "Home")

        let entries = CollectionSettingsList.entries(
            customCollections: [work, home], activeId: home.id)

        #expect(entries.map(\.isActive) == [false, false, true])
    }

    @Test func withNoStoredIdPresetsAreActive() {
        let work = makeCollection(name: "Work")

        let entries = CollectionSettingsList.entries(
            customCollections: [work], activeId: nil)

        #expect(entries.map(\.isActive) == [true, false])
    }

    /// A stored id whose collection is gone (deleted, or synced away)
    /// degrades to the presets — the same resolution the panel applies, so
    /// the marked row is what the panel actually shows.
    @Test func aStaleStoredIdFallsBackToPresets() {
        let work = makeCollection(name: "Work")

        let entries = CollectionSettingsList.entries(
            customCollections: [work], activeId: CollectionId.generate())

        #expect(entries.map(\.isActive) == [true, false])
    }
}
