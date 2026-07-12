import Foundation
import SuttoDomain

@testable import SuttoOperations

/// In-memory ``SpaceCollectionRepository`` for use-case tests: no files
/// involved, and saves can be scripted to fail.
@MainActor
final class InMemorySpaceCollectionRepository: SpaceCollectionRepository {
    var collections: [SpaceCollection] = []
    var saveError: Error?

    func loadCustomCollections() -> [SpaceCollection] {
        collections
    }

    func saveCustomCollections(_ collections: [SpaceCollection]) throws {
        if let saveError {
            throw saveError
        }
        self.collections = collections
    }
}

/// In-memory ``PreferencesRepository`` for use-case tests.
@MainActor
final class InMemoryPreferencesRepository: PreferencesRepository {
    var storedActiveCollectionId: CollectionId?
    var storedPanelToggleShortcut: KeyCombo?

    func activeCollectionId() -> CollectionId? {
        storedActiveCollectionId
    }

    func setActiveCollectionId(_ id: CollectionId?) {
        storedActiveCollectionId = id
    }

    func panelToggleShortcut() -> KeyCombo? {
        storedPanelToggleShortcut
    }

    func setPanelToggleShortcut(_ combo: KeyCombo?) {
        storedPanelToggleShortcut = combo
    }
}

/// ``FileReading`` stub serving canned data or a canned failure.
@MainActor
struct StubFileReader: FileReading {
    var result: Result<Data, Error>

    init(data: Data) {
        result = .success(data)
    }

    init(json: String) {
        result = .success(Data(json.utf8))
    }

    init(error: Error) {
        result = .failure(error)
    }

    func read(from url: URL) throws -> Data {
        try result.get()
    }
}

struct StubError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
