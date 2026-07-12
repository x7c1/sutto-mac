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

    // MARK: - Panel toggle shortcut

    @Test func startsWithNoStoredShortcut() throws {
        try withRepository { repository, _ in
            #expect(repository.panelToggleShortcut() == nil)
        }
    }

    @Test func storedShortcutRoundTrips() throws {
        try withRepository { repository, _ in
            let combo = KeyCombo(keyCode: 40, modifiers: [.control, .command])

            repository.setPanelToggleShortcut(combo)

            #expect(repository.panelToggleShortcut() == combo)
        }
    }

    @Test func settingNilClearsTheShortcut() throws {
        try withRepository { repository, _ in
            repository.setPanelToggleShortcut(KeyCombo(keyCode: 40, modifiers: [.command]))

            repository.setPanelToggleShortcut(nil)

            #expect(repository.panelToggleShortcut() == nil)
        }
    }

    /// Pins the storage format: a dictionary of `keyCode` and `modifiers`
    /// integers under `panelToggleShortcut`. A format change would silently
    /// drop every user's captured shortcut, so it must fail a test.
    @Test func persistsTheDocumentedDictionaryFormat() throws {
        try withRepository { repository, defaults in
            repository.setPanelToggleShortcut(
                KeyCombo(keyCode: 40, modifiers: [.control, .command]))

            let stored = defaults.dictionary(
                forKey: UserDefaultsPreferencesRepository.panelToggleShortcutKey)
            #expect(stored?["keyCode"] as? Int == 40)
            #expect(stored?["modifiers"] as? Int == 0b1001)  // control | command
        }
    }

    /// Same degradation as an invalid collection id: a hand-edited or
    /// corrupt value falls back to "nothing stored" (the caller then uses
    /// the default combo) instead of crashing. (One test over a local list
    /// because `[String: Any]` is not Sendable, which `arguments:` needs.)
    @Test func anInvalidStoredShortcutDegradesToNil() throws {
        let invalidValues: [[String: Any]] = [
            ["keyCode": "not-a-number", "modifiers": 9],  // wrong type
            ["keyCode": 40],  // missing field
            ["keyCode": 99_999, "modifiers": 9],  // keyCode out of UInt16
            ["keyCode": 40, "modifiers": 4096],  // modifiers out of UInt8
        ]
        for stored in invalidValues {
            try withRepository { repository, defaults in
                defaults.set(
                    stored, forKey: UserDefaultsPreferencesRepository.panelToggleShortcutKey)

                #expect(
                    repository.panelToggleShortcut() == nil,
                    "expected nil for \(stored)")
            }
        }
    }
}
