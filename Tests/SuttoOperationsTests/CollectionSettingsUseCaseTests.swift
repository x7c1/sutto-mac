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
}
