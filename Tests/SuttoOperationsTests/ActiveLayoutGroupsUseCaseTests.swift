import SuttoDomain
import Testing

@testable import SuttoOperations

@Suite @MainActor struct ActiveLayoutGroupsUseCaseTests {
    private let repository = InMemorySpaceCollectionRepository()
    private let preferences = InMemoryPreferencesRepository()
    private let presets = BuiltInPresets.standardLayoutGroups

    private func makeUseCase() -> ActiveLayoutGroupsUseCase {
        ActiveLayoutGroupsUseCase(
            repository: repository,
            preferences: preferences,
            presetGroups: presets
        )
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

    /// First run: nothing imported, nothing selected — built-in presets.
    @Test func fallsBackToPresetsWithNoActiveSelection() {
        #expect(makeUseCase().activeLayoutGroups() == presets)
    }

    /// A stale id (collection deleted or defaults carried over) also falls
    /// back, mirroring `getActiveSpaceCollection` falling back to the first
    /// preset when the stored id resolves to nothing.
    @Test func fallsBackToPresetsWhenTheActiveIdIsStale() {
        preferences.storedActiveCollectionId = CollectionId.generate()

        #expect(makeUseCase().activeLayoutGroups() == presets)
    }

    @Test func projectsTheActiveCollection() throws {
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
        let collection = makeCollection(groupName: "disabled group", enabled: false)
        try repository.saveCustomCollections([collection])
        preferences.storedActiveCollectionId = collection.id

        #expect(makeUseCase().activeLayoutGroups().isEmpty)
    }
}
