import SuttoDomain
import Testing

@testable import SuttoOperations

@Suite @MainActor struct ActiveLayoutGroupsUseCaseTests {
    private let repository = InMemorySpaceCollectionRepository()
    private let preferences = InMemoryPreferencesRepository()
    private let screens = StubScreenProvider(screens: [
        StubScreenProvider.screen(width: 1920, height: 1080)
    ])

    private func makeUseCase() -> ActiveLayoutGroupsUseCase {
        ActiveLayoutGroupsUseCase(
            repository: repository,
            preferences: preferences,
            screens: screens
        )
    }

    /// Stores the generated presets the ensure step would have written for
    /// a single monitor.
    private func storeSingleMonitorPresets() {
        repository.presetCollections = [
            PresetGenerator.generate(monitorCount: 1, monitorType: .standard),
            PresetGenerator.generate(monitorCount: 1, monitorType: .wide),
        ]
    }

    private func makeCollection(groupName: String, enabled: Bool = true) -> SpaceCollection {
        SpaceCollection(
            id: .generate(),
            name: "Custom",
            rows: [
                SpacesRow(spaces: [
                    Space(
                        id: .generate(),
                        enabled: enabled,
                        displays: [
                            "0": LayoutGroup(
                                name: groupName,
                                layouts: [
                                    Layout(
                                        label: "Left",
                                        position: LayoutPosition(x: "0", y: "0"),
                                        size: LayoutSize(width: "50%", height: "100%")
                                    )
                                ]
                            )
                        ]
                    )
                ])
            ]
        )
    }

    /// First run on a standard display: nothing imported, nothing selected
    /// — the generated standard preset.
    @Test func fallsBackToTheStandardPresetOnAStandardDisplay() {
        storeSingleMonitorPresets()

        let groups = makeUseCase().activeLayoutGroups()

        #expect(groups.map(\.name) == PresetConfiguration.standardLayoutGroupNames)
    }

    /// The same fallback on an ultrawide (≥ 21:9) display resolves the wide
    /// preset instead.
    @Test func fallsBackToTheWidePresetOnAnUltrawideDisplay() {
        storeSingleMonitorPresets()
        screens.stubbedScreens = [StubScreenProvider.screen(width: 3440, height: 1440)]

        let groups = makeUseCase().activeLayoutGroups()

        #expect(groups.map(\.name) == PresetConfiguration.wideLayoutGroupNames)
    }

    /// An explicitly selected preset beats the default classification —
    /// the laptop-plus-ultrawide case: the primary is standard, so the
    /// default would be the standard preset, but the user selected the
    /// wide one in settings.
    @Test func showsAnExplicitlySelectedPresetOverTheDefault() {
        storeSingleMonitorPresets()
        let widePreset = repository.presetCollections[1]
        preferences.storedActiveCollectionId = widePreset.id

        let groups = makeUseCase().activeLayoutGroups()

        #expect(groups.map(\.name) == PresetConfiguration.wideLayoutGroupNames)
    }

    /// A selected preset stays active even when the monitor count changed
    /// since — the id still resolves, exactly like a GNOME
    /// `findCollectionById` hit. Only a stale id falls back to the default.
    @Test func aSelectedPresetSurvivesAMonitorCountChange() {
        storeSingleMonitorPresets()
        let widePreset = repository.presetCollections[1]
        preferences.storedActiveCollectionId = widePreset.id
        screens.stubbedScreens = [
            StubScreenProvider.screen(width: 1920, height: 1080),
            StubScreenProvider.screen(width: 1920, height: 1080),
        ]

        let groups = makeUseCase().activeLayoutGroups()

        #expect(groups.map(\.name) == PresetConfiguration.wideLayoutGroupNames)
    }

    /// A stale id (collection deleted or defaults carried over) also falls
    /// back, mirroring `getActiveSpaceCollection` falling back to a preset
    /// when the stored id resolves to nothing.
    @Test func fallsBackToThePresetWhenTheActiveIdIsStale() {
        storeSingleMonitorPresets()
        preferences.storedActiveCollectionId = CollectionId.generate()

        let groups = makeUseCase().activeLayoutGroups()

        #expect(groups.map(\.name) == PresetConfiguration.standardLayoutGroupNames)
    }

    /// No preset matches the current configuration (say, a second monitor
    /// arrived and no ensure ran yet): the first stored preset stands in —
    /// the GNOME `presets[0]` fallback.
    @Test func fallsBackToTheFirstPresetWhenNoNameMatches() {
        repository.presetCollections = [
            PresetGenerator.generate(monitorCount: 2, monitorType: .standard),
            PresetGenerator.generate(monitorCount: 2, monitorType: .wide),
        ]

        let groups = makeUseCase().activeLayoutGroups()

        #expect(groups.map(\.name) == PresetConfiguration.standardLayoutGroupNames)
    }

    /// No monitors at all (every display detached): the first stored preset
    /// still renders rather than an empty panel.
    @Test func fallsBackToTheFirstPresetWithoutScreens() {
        storeSingleMonitorPresets()
        screens.stubbedScreens = []

        let groups = makeUseCase().activeLayoutGroups()

        #expect(groups.map(\.name) == PresetConfiguration.standardLayoutGroupNames)
    }

    /// Nothing stored (the ensure never ran or could not save): an empty
    /// panel, matching the GNOME panel with no collection resolved.
    @Test func rendersEmptyWithoutStoredPresets() {
        #expect(makeUseCase().activeLayoutGroups().isEmpty)
    }

    @Test func projectsTheActiveCollection() throws {
        storeSingleMonitorPresets()
        let collection = makeCollection(groupName: "imported group")
        try repository.saveCustomCollections([collection])
        preferences.storedActiveCollectionId = collection.id

        let groups = makeUseCase().activeLayoutGroups()

        #expect(groups.map(\.name) == ["imported group"])
    }

    @Test func picksTheActiveCollectionAmongSeveral() throws {
        let first = makeCollection(groupName: "first")
        let second = makeCollection(groupName: "second")
        try repository.saveCustomCollections([first, second])
        preferences.storedActiveCollectionId = second.id

        let groups = makeUseCase().activeLayoutGroups()

        #expect(groups.map(\.name) == ["second"])
    }

    /// An active collection whose projection is empty (every space
    /// disabled) yields an empty panel, not the presets — the same as the
    /// GNOME panel rendering an active collection with everything filtered
    /// out. Only a *missing* collection falls back.
    @Test func anEmptyProjectionDoesNotFallBackToPresets() throws {
        storeSingleMonitorPresets()
        let collection = makeCollection(groupName: "disabled group", enabled: false)
        try repository.saveCustomCollections([collection])
        preferences.storedActiveCollectionId = collection.id

        #expect(makeUseCase().activeLayoutGroups().isEmpty)
    }
}
