import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

@Suite @MainActor struct CollectionSettingsUseCaseTests {
    private let repository = InMemorySpaceCollectionRepository()
    private let preferences = InMemoryPreferencesRepository()
    private let screens = StubScreenProvider(screens: [
        StubScreenProvider.screen(width: 1920, height: 1080)
    ])
    private let environmentRepository = InMemoryMonitorEnvironmentRepository()
    private let environment: MonitorEnvironmentUseCase

    private var useCase: CollectionSettingsUseCase {
        CollectionSettingsUseCase(
            repository: repository, preferences: preferences, screens: screens,
            environment: environment)
    }

    private var standardPreset: SpaceCollection { repository.presetCollections[0] }
    private var widePreset: SpaceCollection { repository.presetCollections[1] }

    init() {
        repository.presetCollections = [
            PresetGenerator.generate(monitorCount: 1, monitorType: .standard),
            PresetGenerator.generate(monitorCount: 1, monitorType: .wide),
        ]
        environment = MonitorEnvironmentUseCase(
            screens: screens, repository: environmentRepository, preferences: preferences)
        // A detected current environment, so selections have somewhere to
        // be recorded — the launch step the app performs.
        environment.activateEnvironmentForCurrentScreens()
    }

    private func addCollection(name: String) throws -> SpaceCollection {
        try repository.addCustomCollection(name: name, rows: [])
    }

    // MARK: - Listing

    @Test func listsEveryPresetPlusCustomCollections() throws {
        let work = try addCollection(name: "Work")
        preferences.storedActiveCollectionId = work.id

        let entries = useCase.entries()

        #expect(
            entries == [
                CollectionSettingsEntry(
                    kind: .preset(standardPreset.id), name: "1 Monitor - Standard",
                    isActive: false),
                CollectionSettingsEntry(
                    kind: .preset(widePreset.id), name: "1 Monitor - Wide", isActive: false),
                CollectionSettingsEntry(kind: .custom(work.id), name: "Work", isActive: true),
            ])
    }

    /// No stored selection: the default preset (classified off the primary
    /// display) is the active row.
    @Test func withNoSelectionTheDefaultPresetRowIsActive() {
        let entries = useCase.entries()

        #expect(entries.map(\.isActive) == [true, false])
    }

    /// The same list on an ultrawide primary marks the wide preset active.
    @Test func theDefaultRowFollowsThePrimaryDisplayClass() {
        screens.stubbedScreens = [StubScreenProvider.screen(width: 3440, height: 1440)]

        let entries = useCase.entries()

        #expect(entries.map(\.isActive) == [false, true])
    }

    // MARK: - Selection

    @Test func selectingACustomCollectionStoresItsId() throws {
        let work = try addCollection(name: "Work")

        useCase.select(
            CollectionSettingsEntry(kind: .custom(work.id), name: "Work", isActive: false))

        #expect(preferences.storedActiveCollectionId == work.id)
    }

    /// Selecting a preset stores its id exactly like a custom collection —
    /// the explicit selection GNOME's preferences offer. This is how a
    /// standard-primary setup gets the wide preset: the default would never
    /// pick it, the user does.
    @Test func selectingAPresetStoresItsId() {
        useCase.select(
            CollectionSettingsEntry(
                kind: .preset(widePreset.id), name: "1 Monitor - Wide", isActive: false))

        #expect(preferences.storedActiveCollectionId == widePreset.id)
        #expect(useCase.entries().map(\.isActive) == [false, true])
    }

    /// A selection is also recorded against the current monitor
    /// environment, so returning to this display setup later restores it.
    @Test func selectingRecordsTheCollectionForTheCurrentEnvironment() throws {
        let work = try addCollection(name: "Work")

        useCase.select(
            CollectionSettingsEntry(kind: .custom(work.id), name: "Work", isActive: false))

        #expect(
            environmentRepository.storedStorage?.currentEnvironment?.lastActiveCollectionId
                == work.id)
    }

    // MARK: - Deletion

    @Test func deletesACustomCollection() throws {
        let work = try addCollection(name: "Work")
        let home = try addCollection(name: "Home")

        try useCase.deleteCollection(work.id)

        #expect(repository.collections == [home])
    }

    /// Deleting the active collection falls back to the default preset,
    /// like the GNOME preferences re-selecting a preset after a delete.
    @Test func deletingTheActiveCollectionFallsBackToTheDefaultPreset() throws {
        let work = try addCollection(name: "Work")
        preferences.storedActiveCollectionId = work.id

        try useCase.deleteCollection(work.id)

        #expect(preferences.storedActiveCollectionId == nil)
        #expect(useCase.entries().first?.isActive == true)
    }

    /// Deleting the active collection also clears the current
    /// environment's memory of it — a dead id must not be restored on the
    /// next environment switch.
    @Test func deletingTheActiveCollectionClearsTheEnvironmentRecord() throws {
        let work = try addCollection(name: "Work")
        preferences.storedActiveCollectionId = work.id
        environment.recordActiveCollection(work.id)

        try useCase.deleteCollection(work.id)

        #expect(
            environmentRepository.storedStorage?.currentEnvironment?.lastActiveCollectionId
                == nil)
    }

    @Test func deletingAnInactiveCollectionKeepsTheActiveOne() throws {
        let work = try addCollection(name: "Work")
        let home = try addCollection(name: "Home")
        preferences.storedActiveCollectionId = home.id

        try useCase.deleteCollection(work.id)

        #expect(preferences.storedActiveCollectionId == home.id)
    }

    /// Deleting an id that no longer exists is a quiet no-op (the GNOME
    /// repository logs and returns false).
    @Test func deletingAMissingCollectionChangesNothing() throws {
        let work = try addCollection(name: "Work")
        preferences.storedActiveCollectionId = work.id

        try useCase.deleteCollection(.generate())

        #expect(repository.collections == [work])
        #expect(preferences.storedActiveCollectionId == work.id)
    }

    /// A failed save must not clear the active id: the collection is still
    /// on disk, so the selection is still valid.
    @Test func aFailedDeleteKeepsTheActiveId() throws {
        let work = try addCollection(name: "Work")
        preferences.storedActiveCollectionId = work.id
        repository.saveError = StubError(message: "disk full")

        #expect(throws: StubError.self) {
            try useCase.deleteCollection(work.id)
        }
        #expect(preferences.storedActiveCollectionId == work.id)
    }

    // MARK: - Space toggling

    private func firstSpaceId(of collection: SpaceCollection) throws -> SpaceId {
        try #require(collection.rows.first?.spaces.first?.id)
    }

    /// Toggling a preset's space persists through the preset file — GNOME's
    /// `updateSpaceEnabled` covers generated presets, not just customs.
    @Test func togglingAPresetSpaceDisablesAndPersistsIt() throws {
        let spaceId = try firstSpaceId(of: standardPreset)

        try useCase.toggleSpace(collectionId: standardPreset.id, spaceId: spaceId)

        #expect(repository.presetCollections[0].space(withId: spaceId)?.enabled == false)
    }

    @Test func togglingACustomSpaceDisablesAndPersistsIt() throws {
        let custom = try repository.addCustomCollection(
            name: "Work",
            rows: [SpacesRow(spaces: [Space(id: .generate(), enabled: true, displays: [:])])]
        )
        let spaceId = try firstSpaceId(of: custom)

        try useCase.toggleSpace(collectionId: custom.id, spaceId: spaceId)

        #expect(repository.collections[0].space(withId: spaceId)?.enabled == false)
        // Presets stay untouched: the write lands in the customs file only.
        #expect(
            repository.presetCollections.flatMap(\.rows).flatMap(\.spaces)
                .allSatisfy { $0.enabled })
    }

    /// Toggle is a flip of the *stored* state: twice restores the original.
    @Test func togglingTwiceRestoresTheSpace() throws {
        let spaceId = try firstSpaceId(of: standardPreset)

        try useCase.toggleSpace(collectionId: standardPreset.id, spaceId: spaceId)
        try useCase.toggleSpace(collectionId: standardPreset.id, spaceId: spaceId)

        #expect(repository.presetCollections[0].space(withId: spaceId)?.enabled == true)
    }

    /// Disabling every space is allowed — the GNOME preferences let you —
    /// and the panel model then renders empty (its "no spaces" message),
    /// pinning the all-disabled edge end to end.
    @Test func disablingEverySpaceLeavesThePanelModelEmpty() throws {
        preferences.storedActiveCollectionId = standardPreset.id
        for space in standardPreset.rows.flatMap(\.spaces) {
            try useCase.toggleSpace(collectionId: standardPreset.id, spaceId: space.id)
        }

        let panelModel = ActivePanelModelUseCase(
            repository: repository, preferences: preferences, screens: screens,
            environment: environment
        ).panelModel()

        #expect(panelModel.rows.isEmpty)
        // The preview still shows every space, all dimmed, for re-enabling.
        let preview = try #require(useCase.previewModel())
        #expect(preview.rows.flatMap(\.spaces).allSatisfy { !$0.enabled })
    }

    /// An unknown space id is a quiet no-op, like the GNOME
    /// `updateSpaceEnabled` returning false.
    @Test func togglingAMissingSpaceChangesNothing() throws {
        let before = repository.presetCollections

        try useCase.toggleSpace(collectionId: standardPreset.id, spaceId: .generate())
        try useCase.toggleSpace(collectionId: .generate(), spaceId: .generate())

        #expect(repository.presetCollections == before)
    }

    /// A failed save surfaces to the caller (the settings window alerts);
    /// the in-memory state stays what is on disk.
    @Test func aFailedToggleSaveThrows() throws {
        let spaceId = try firstSpaceId(of: standardPreset)
        repository.saveError = StubError(message: "disk full")

        #expect(throws: StubError.self) {
            try useCase.toggleSpace(collectionId: standardPreset.id, spaceId: spaceId)
        }
    }

    // MARK: - Preview

    /// The preview shows the collection the panel resolves: the stored
    /// selection, or the default preset without one — including its
    /// disabled spaces, which the panel filters out.
    @Test func previewsTheActiveCollectionIncludingDisabledSpaces() throws {
        let spaceId = try firstSpaceId(of: standardPreset)
        try useCase.toggleSpace(collectionId: standardPreset.id, spaceId: spaceId)

        let preview = try #require(useCase.previewModel())

        #expect(preview.collectionId == standardPreset.id)
        let entries = preview.rows.flatMap(\.spaces)
        #expect(entries.count == standardPreset.rows.flatMap(\.spaces).count)
        #expect(entries.contains { !$0.enabled })
    }

    @Test func previewsTheStoredSelection() throws {
        let custom = try repository.addCustomCollection(
            name: "Work",
            rows: [SpacesRow(spaces: [Space(id: .generate(), enabled: true, displays: [:])])]
        )
        preferences.storedActiveCollectionId = custom.id

        #expect(useCase.previewModel()?.collectionId == custom.id)
    }

    @Test func previewIsNilWithoutAnyCollection() {
        repository.presetCollections = []

        #expect(useCase.previewModel() == nil)
    }
}
