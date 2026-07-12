import Foundation
import SuttoDomain
import Testing

@testable import SuttoInfra

@Suite @MainActor struct UserDefaultsPreferencesRepositoryTests {
    /// Runs `body` against a repository over an isolated defaults suite,
    /// wiping the suite afterwards so nothing leaks between tests or into
    /// the developer's real defaults.
    private func withRepository(
        _ body: (UserDefaultsPreferencesRepository, UserDefaults) throws -> Void
    ) throws {
        let suiteName = "io.github.x7c1.SuttoMac.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try body(UserDefaultsPreferencesRepository(defaults: defaults), defaults)
    }

    @Test func startsWithNoActiveCollection() throws {
        try withRepository { repository, _ in
            #expect(repository.activeCollectionId() == nil)
        }
    }

    @Test func storedIdRoundTrips() throws {
        try withRepository { repository, _ in
            let id = CollectionId.generate()

            repository.setActiveCollectionId(id)

            #expect(repository.activeCollectionId() == id)
        }
    }

    @Test func settingNilClearsTheSelection() throws {
        try withRepository { repository, _ in
            repository.setActiveCollectionId(.generate())

            repository.setActiveCollectionId(nil)

            #expect(repository.activeCollectionId() == nil)
        }
    }

    /// GNOME parity: `getActiveCollectionId` returns null for a string
    /// GSettings holds but `CollectionId` rejects; an invalid stored value
    /// degrades to "no selection" here too.
    @Test func anInvalidStoredValueDegradesToNil() throws {
        try withRepository { repository, defaults in
            defaults.set(
                "not-a-uuid", forKey: UserDefaultsPreferencesRepository.activeCollectionIdKey)

            #expect(repository.activeCollectionId() == nil)
        }
    }

    /// An uppercase id stored by hand still resolves, thanks to the
    /// ``CollectionId`` normalization shared with the GNOME version.
    @Test func normalizesACasedStoredValue() throws {
        try withRepository { repository, defaults in
            defaults.set(
                "123E4567-E89B-42D3-A456-426614174000",
                forKey: UserDefaultsPreferencesRepository.activeCollectionIdKey)

            let id = try CollectionId("123e4567-e89b-42d3-a456-426614174000")
            #expect(repository.activeCollectionId() == id)
        }
    }
}
