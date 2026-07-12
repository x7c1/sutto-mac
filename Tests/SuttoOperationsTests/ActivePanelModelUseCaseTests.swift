import SuttoDomain
import Testing

@testable import SuttoOperations

@Suite @MainActor struct ActivePanelModelUseCaseTests {
    private let repository = InMemorySpaceCollectionRepository()
    private let preferences = InMemoryPreferencesRepository()
    private let screens = StubScreenProvider(screens: [
        StubScreenProvider.screen(width: 1920, height: 1080)
    ])

    private func makeUseCase() -> ActivePanelModelUseCase {
        ActivePanelModelUseCase(
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
                                        label: "\(groupName) layout",
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

    /// The region labels of each space's first display, in reading order —
    /// the miniature model's equivalent of "which layout groups render, in
    /// which order".
    private func renderedLabels(_ model: MiniaturePanelModel) -> [[String]] {
        model.rows.flatMap(\.spaces).map { space in
            (space.displays.first?.regions ?? []).map(\.layout.label)
        }
    }

    /// What the preset with the given group-name list should render.
    private func expectedLabels(forGroupNames names: [String]) -> [[String]] {
        names.map { name in
            PresetConfiguration.baseLayoutGroups
                .first { $0.name == name }!
                .layouts.map(\.label)
        }
    }

    /// First run on a standard display: nothing imported, nothing selected
    /// — the generated standard preset.
    @Test func fallsBackToTheStandardPresetOnAStandardDisplay() {
        storeSingleMonitorPresets()

        let model = makeUseCase().panelModel()

        #expect(
            renderedLabels(model)
                == expectedLabels(forGroupNames: PresetConfiguration.standardLayoutGroupNames))
    }

    /// The same fallback on an ultrawide (≥ 21:9) display resolves the wide
    /// preset instead.
    @Test func fallsBackToTheWidePresetOnAnUltrawideDisplay() {
        storeSingleMonitorPresets()
        screens.stubbedScreens = [StubScreenProvider.screen(width: 3440, height: 1440)]

        let model = makeUseCase().panelModel()

        #expect(
            renderedLabels(model)
                == expectedLabels(forGroupNames: PresetConfiguration.wideLayoutGroupNames))
    }

    /// An explicitly selected preset beats the default classification —
    /// the laptop-plus-ultrawide case: the primary is standard, so the
    /// default would be the standard preset, but the user selected the
    /// wide one in settings.
    @Test func showsAnExplicitlySelectedPresetOverTheDefault() {
        storeSingleMonitorPresets()
        let widePreset = repository.presetCollections[1]
        preferences.storedActiveCollectionId = widePreset.id

        let model = makeUseCase().panelModel()

        #expect(
            renderedLabels(model)
                == expectedLabels(forGroupNames: PresetConfiguration.wideLayoutGroupNames))
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

        let model = makeUseCase().panelModel()

        #expect(
            renderedLabels(model)
                == expectedLabels(forGroupNames: PresetConfiguration.wideLayoutGroupNames))
    }

    /// A stale id (collection deleted or defaults carried over) also falls
    /// back, mirroring `getActiveSpaceCollection` falling back to a preset
    /// when the stored id resolves to nothing.
    @Test func fallsBackToThePresetWhenTheActiveIdIsStale() {
        storeSingleMonitorPresets()
        preferences.storedActiveCollectionId = CollectionId.generate()

        let model = makeUseCase().panelModel()

        #expect(
            renderedLabels(model)
                == expectedLabels(forGroupNames: PresetConfiguration.standardLayoutGroupNames))
    }

    /// No preset matches the current configuration (say, a second monitor
    /// arrived and no ensure ran yet): the first stored preset stands in —
    /// the GNOME `presets[0]` fallback.
    @Test func fallsBackToTheFirstPresetWhenNoNameMatches() {
        repository.presetCollections = [
            PresetGenerator.generate(monitorCount: 2, monitorType: .standard),
            PresetGenerator.generate(monitorCount: 2, monitorType: .wide),
        ]

        let model = makeUseCase().panelModel()

        #expect(
            renderedLabels(model)
                == expectedLabels(forGroupNames: PresetConfiguration.standardLayoutGroupNames))
    }

    /// No monitors at all (every display detached): the first stored preset
    /// still renders rather than an empty panel.
    @Test func fallsBackToTheFirstPresetWithoutScreens() {
        storeSingleMonitorPresets()
        screens.stubbedScreens = []

        let model = makeUseCase().panelModel()

        #expect(
            renderedLabels(model)
                == expectedLabels(forGroupNames: PresetConfiguration.standardLayoutGroupNames))
    }

    /// Nothing stored (the ensure never ran or could not save): an empty
    /// panel, matching the GNOME panel with no collection resolved.
    @Test func rendersEmptyWithoutStoredPresets() {
        #expect(makeUseCase().panelModel().rows.isEmpty)
    }

    @Test func rendersTheActiveCollection() throws {
        storeSingleMonitorPresets()
        let collection = makeCollection(groupName: "imported group")
        try repository.saveCustomCollections([collection])
        preferences.storedActiveCollectionId = collection.id

        let model = makeUseCase().panelModel()

        #expect(renderedLabels(model) == [["imported group layout"]])
    }

    @Test func picksTheActiveCollectionAmongSeveral() throws {
        let first = makeCollection(groupName: "first")
        let second = makeCollection(groupName: "second")
        try repository.saveCustomCollections([first, second])
        preferences.storedActiveCollectionId = second.id

        let model = makeUseCase().panelModel()

        #expect(renderedLabels(model) == [["second layout"]])
    }

    /// An active collection that renders empty (every space disabled)
    /// yields an empty panel, not the presets — the same as the GNOME
    /// panel rendering an active collection with everything filtered out.
    /// Only a *missing* collection falls back.
    @Test func anEmptyCollectionDoesNotFallBackToPresets() throws {
        storeSingleMonitorPresets()
        let collection = makeCollection(groupName: "disabled group", enabled: false)
        try repository.saveCustomCollections([collection])
        preferences.storedActiveCollectionId = collection.id

        #expect(makeUseCase().panelModel().rows.isEmpty)
    }

    /// The model reflects the live screens: the same collection projects
    /// onto whatever arrangement is connected when the panel opens.
    @Test func reflectsTheCurrentScreensOnEveryCall() throws {
        let group = LayoutGroup(
            name: "dual",
            layouts: [
                Layout(
                    label: "Full",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "100%", height: "100%")
                )
            ]
        )
        let collection = SpaceCollection(
            id: .generate(),
            name: "Dual",
            rows: [
                SpacesRow(spaces: [
                    Space(id: .generate(), enabled: true, displays: ["0": group, "1": group])
                ])
            ]
        )
        try repository.saveCustomCollections([collection])
        preferences.storedActiveCollectionId = collection.id
        let useCase = makeUseCase()

        let single = useCase.panelModel()
        #expect(
            single.rows.first?.spaces.first?.displays.map(\.isConnected) == [true, false])

        screens.stubbedScreens = [
            StubScreenProvider.screen(width: 1920, height: 1080),
            StubScreenProvider.screen(width: 1920, height: 1080),
        ]
        let dual = useCase.panelModel()
        #expect(
            dual.rows.first?.spaces.first?.displays.map(\.isConnected) == [true, true])
    }
}
