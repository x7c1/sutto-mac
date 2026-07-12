import Testing

@testable import SuttoDomain

@Suite struct CollectionSettingsListTests {
    private func makeCollection(name: String) -> SpaceCollection {
        SpaceCollection(id: .generate(), name: name, rows: [])
    }

    private let standard = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)
    private let wide = PresetGenerator.generate(monitorCount: 1, monitorType: .wide)

    @Test func listsEveryPresetThenCustomsInStoredOrder() {
        let work = makeCollection(name: "Work")
        let home = makeCollection(name: "Home")

        let entries = CollectionSettingsList.entries(
            presetCollections: [standard, wide],
            customCollections: [work, home],
            activeId: nil,
            defaultPresetId: standard.id
        )

        #expect(
            entries.map(\.name) == [
                "1 Monitor - Standard", "1 Monitor - Wide", "Work", "Home",
            ])
        #expect(
            entries.map(\.kind) == [
                .preset(standard.id), .preset(wide.id), .custom(work.id), .custom(home.id),
            ])
    }

    /// No stored selection: the default preset row is the active one — the
    /// same resolution the panel applies.
    @Test func withNoStoredIdTheDefaultPresetIsActive() {
        let entries = CollectionSettingsList.entries(
            presetCollections: [standard, wide],
            customCollections: [makeCollection(name: "Work")],
            activeId: nil,
            defaultPresetId: wide.id
        )

        #expect(entries.map(\.isActive) == [false, true, false])
    }

    /// An explicitly selected preset wins over the default — this is the
    /// laptop-plus-ultrawide case: the default classifies off the standard
    /// primary, but the user selected the wide preset.
    @Test func aStoredPresetIdMarksThatPresetActive() {
        let entries = CollectionSettingsList.entries(
            presetCollections: [standard, wide],
            customCollections: [],
            activeId: wide.id,
            defaultPresetId: standard.id
        )

        #expect(entries.map(\.isActive) == [false, true])
    }

    @Test func marksTheStoredCustomCollectionActive() {
        let work = makeCollection(name: "Work")
        let home = makeCollection(name: "Home")

        let entries = CollectionSettingsList.entries(
            presetCollections: [standard],
            customCollections: [work, home],
            activeId: home.id,
            defaultPresetId: standard.id
        )

        #expect(entries.map(\.isActive) == [false, false, true])
    }

    /// A stored id whose collection is gone (deleted, or synced away)
    /// degrades to the default preset — the same resolution the panel
    /// applies, so the marked row is what the panel actually shows.
    @Test func aStaleStoredIdFallsBackToTheDefaultPreset() {
        let work = makeCollection(name: "Work")

        let entries = CollectionSettingsList.entries(
            presetCollections: [standard, wide],
            customCollections: [work],
            activeId: CollectionId.generate(),
            defaultPresetId: standard.id
        )

        #expect(entries.map(\.isActive) == [true, false, false])
    }

    /// No presets stored at all (the ensure never ran): the list is just
    /// the customs, none force-marked active.
    @Test func withoutPresetsTheListIsJustCustoms() {
        let work = makeCollection(name: "Work")

        let entries = CollectionSettingsList.entries(
            presetCollections: [],
            customCollections: [work],
            activeId: nil,
            defaultPresetId: nil
        )

        #expect(entries.map(\.name) == ["Work"])
        #expect(entries.map(\.isActive) == [false])
    }
}
