import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

@Suite @MainActor struct CollectionSettingsUseCaseTests {
    private let repository = InMemorySpaceCollectionRepository()
    private let preferences = InMemoryPreferencesRepository()

    private var useCase: CollectionSettingsUseCase {
        CollectionSettingsUseCase(repository: repository, preferences: preferences)
    }

    private func addCollection(name: String) throws -> SpaceCollection {
        try repository.addCustomCollection(name: name, rows: [])
    }

    // MARK: - Listing

    @Test func listsPresetsPlusCustomCollections() throws {
        let work = try addCollection(name: "Work")
        preferences.storedActiveCollectionId = work.id

        let entries = useCase.entries()

        #expect(
            entries == [
                CollectionSettingsEntry(kind: .presets, name: "Presets", isActive: false),
                CollectionSettingsEntry(kind: .custom(work.id), name: "Work", isActive: true),
            ])
    }

    // MARK: - Selection

    @Test func selectingACustomCollectionStoresItsId() throws {
        let work = try addCollection(name: "Work")

        useCase.select(
            CollectionSettingsEntry(kind: .custom(work.id), name: "Work", isActive: false))

        #expect(preferences.storedActiveCollectionId == work.id)
    }

    /// Selecting the presets row clears the stored id — "no selection" is
    /// the presets-fallback state the panel resolves.
    @Test func selectingPresetsClearsTheStoredId() throws {
        let work = try addCollection(name: "Work")
        preferences.storedActiveCollectionId = work.id

        useCase.select(
            CollectionSettingsEntry(kind: .presets, name: "Presets", isActive: false))

        #expect(preferences.storedActiveCollectionId == nil)
    }

    // MARK: - Deletion

    @Test func deletesACustomCollection() throws {
        let work = try addCollection(name: "Work")
        let home = try addCollection(name: "Home")

        try useCase.deleteCollection(work.id)

        #expect(repository.collections == [home])
    }

    /// Deleting the active collection falls back to the presets, like the
    /// GNOME preferences re-selecting its first preset after a delete.
    @Test func deletingTheActiveCollectionFallsBackToPresets() throws {
        let work = try addCollection(name: "Work")
        preferences.storedActiveCollectionId = work.id

        try useCase.deleteCollection(work.id)

        #expect(preferences.storedActiveCollectionId == nil)
        #expect(useCase.entries().first?.isActive == true)
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
