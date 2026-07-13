import Foundation
import SuttoDomain

@testable import SuttoOperations

/// In-memory ``SpaceCollectionRepository`` for use-case tests: no files
/// involved, and saves can be scripted to fail.
@MainActor
final class InMemorySpaceCollectionRepository: SpaceCollectionRepository {
    var presetCollections: [SpaceCollection] = []
    var collections: [SpaceCollection] = []
    var saveError: Error?

    func loadPresetCollections() -> [SpaceCollection] {
        presetCollections
    }

    func savePresetCollections(_ collections: [SpaceCollection]) throws {
        if let saveError {
            throw saveError
        }
        presetCollections = collections
    }

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

/// Scriptable ``ScreenProviding`` for use-case tests: whatever display
/// arrangement a test needs, no AppKit involved.
@MainActor
final class StubScreenProvider: ScreenProviding {
    var stubbedScreens: [Screen]

    init(screens: [Screen] = []) {
        stubbedScreens = screens
    }

    /// A landscape screen of the given size at the AppKit origin.
    static func screen(width: Double, height: Double) -> Screen {
        Screen(
            frame: PixelRect(x: 0, y: 0, width: width, height: height),
            visibleFrame: PixelRect(x: 0, y: 25, width: width, height: height - 25)
        )
    }

    func screens() -> [Screen] {
        stubbedScreens
    }

    func mouseLocation() -> PixelPoint {
        PixelPoint(x: 0, y: 0)
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

/// In-memory ``MonitorEnvironmentRepository`` for use-case tests: keeps
/// the saved storage inspectable, and saves can be scripted to fail.
@MainActor
final class InMemoryMonitorEnvironmentRepository: MonitorEnvironmentRepository {
    var storedStorage: MonitorEnvironmentStorage?
    var saveError: Error?

    func load() -> MonitorEnvironmentStorage? {
        storedStorage
    }

    func save(_ storage: MonitorEnvironmentStorage) throws {
        if let saveError {
            throw saveError
        }
        storedStorage = storage
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
