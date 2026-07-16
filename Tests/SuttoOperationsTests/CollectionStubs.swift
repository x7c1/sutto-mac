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

/// In-memory ``LayoutHistoryRepository`` for use-case tests: `load()` serves
/// the scripted history and counts how often it was called (to prove the lazy
/// load happens once), `save(_:)` records every persisted history and can be
/// scripted to fail.
@MainActor
final class InMemoryLayoutHistoryRepository: LayoutHistoryRepository {
    var storedHistory: LayoutHistory
    var saveError: Error?
    private(set) var loadCount = 0
    private(set) var savedHistories: [LayoutHistory] = []

    init(history: LayoutHistory = LayoutHistory()) {
        storedHistory = history
    }

    func load() -> LayoutHistory {
        loadCount += 1
        return storedHistory
    }

    func save(_ history: LayoutHistory) throws {
        if let saveError {
            throw saveError
        }
        storedHistory = history
        savedHistories.append(history)
    }
}

/// A ``TargetWindow`` stub the window-controller stub hands back on capture.
private final class StubTargetWindow: TargetWindow {}

/// ``WindowControlling`` stub with a scriptable identity, so tests that need a
/// captured ``PanelTargetSession`` can control what the session snapshots.
@MainActor
final class StubWindowController: WindowControlling {
    var scriptedIdentity: WindowIdentity
    private let target = StubTargetWindow()

    init(identity: WindowIdentity) {
        scriptedIdentity = identity
    }

    func captureFocusedWindow() -> TargetWindow? { target }
    func identity(of window: TargetWindow) -> WindowIdentity { scriptedIdentity }
    func frame(of window: TargetWindow) -> PixelRect? { nil }
    func applyFrame(_ frame: PixelRect, to window: TargetWindow) -> Bool { true }
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
