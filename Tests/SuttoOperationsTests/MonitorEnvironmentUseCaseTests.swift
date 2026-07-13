import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

/// ``MonitorEnvironmentUseCase``: detection wired to the screens, the
/// preference repointing on a switch, and persistence — the docking
/// scenarios the feature exists for, on stubs.
@Suite @MainActor struct MonitorEnvironmentUseCaseTests {
    private let preferences = InMemoryPreferencesRepository()
    private let repository = InMemoryMonitorEnvironmentRepository()
    private let screens: StubScreenProvider
    private let useCase: MonitorEnvironmentUseCase

    /// The laptop display alone…
    private static let laptop = [StubScreenProvider.screen(width: 1512, height: 982)]

    /// …and the desk setup: laptop plus an ultrawide to its right.
    private static let desk = [
        StubScreenProvider.screen(width: 1512, height: 982),
        Screen(
            frame: PixelRect(x: 1512, y: 0, width: 3440, height: 1440),
            visibleFrame: PixelRect(x: 1512, y: 0, width: 3440, height: 1415)
        ),
    ]

    private let customCollection = CollectionId.generate()
    private let otherCollection = CollectionId.generate()

    init() {
        screens = StubScreenProvider(screens: Self.desk)
        useCase = MonitorEnvironmentUseCase(
            screens: screens, repository: repository, preferences: preferences)
    }

    // MARK: - Launch

    /// First launch after this feature ships: the single pre-existing
    /// `activeSpaceCollectionId` preference migrates into the detected
    /// environment's record, and the selection itself is untouched.
    @Test func theFirstActivationMigratesTheExistingSelection() {
        preferences.storedActiveCollectionId = customCollection

        let change = useCase.activateEnvironmentForCurrentScreens()

        #expect(change == .unchanged)
        #expect(preferences.storedActiveCollectionId == customCollection)
        #expect(
            repository.storedStorage?.currentEnvironment?.lastActiveCollectionId
                == customCollection)
    }

    /// Relaunching in the environment the app last ran in changes nothing.
    @Test func relaunchingInTheSameEnvironmentIsUnchanged() {
        preferences.storedActiveCollectionId = customCollection
        useCase.activateEnvironmentForCurrentScreens()

        // A fresh instance over the same persisted storage: a relaunch.
        let relaunched = MonitorEnvironmentUseCase(
            screens: screens, repository: repository, preferences: preferences)

        #expect(relaunched.activateEnvironmentForCurrentScreens() == .unchanged)
        #expect(preferences.storedActiveCollectionId == customCollection)
    }

    /// Quitting at the desk and relaunching on the laptop alone is an
    /// environment switch too — the storage remembers which environment
    /// was current across runs.
    @Test func relaunchingInAnotherEnvironmentSwitches() {
        preferences.storedActiveCollectionId = customCollection
        useCase.activateEnvironmentForCurrentScreens()

        screens.stubbedScreens = Self.laptop
        let relaunched = MonitorEnvironmentUseCase(
            screens: screens, repository: repository, preferences: preferences)

        #expect(
            relaunched.activateEnvironmentForCurrentScreens() == .switched(restoring: nil))
        #expect(preferences.storedActiveCollectionId == nil)
    }

    // MARK: - Switching

    /// Unplugging into an environment never seen: the selection clears, so
    /// the panel falls back to the default preset for the new setup.
    @Test func switchingToAnUnknownEnvironmentClearsTheSelection() {
        preferences.storedActiveCollectionId = customCollection
        useCase.activateEnvironmentForCurrentScreens()

        screens.stubbedScreens = Self.laptop
        let change = useCase.activateEnvironmentForCurrentScreens()

        #expect(change == .switched(restoring: nil))
        #expect(preferences.storedActiveCollectionId == nil)
    }

    /// The full docking round trip: each environment gets its selection
    /// back automatically when its displays return.
    @Test func switchingBackAndForthRestoresEachEnvironmentsSelection() {
        // At the desk, the user works with a custom collection.
        preferences.storedActiveCollectionId = customCollection
        useCase.activateEnvironmentForCurrentScreens()

        // Undock: unknown environment, selection cleared; the user picks
        // another collection there (settings write the preference and
        // record it against the environment).
        screens.stubbedScreens = Self.laptop
        useCase.activateEnvironmentForCurrentScreens()
        preferences.storedActiveCollectionId = otherCollection
        useCase.recordActiveCollection(otherCollection)

        // Redock: the desk collection is restored automatically.
        screens.stubbedScreens = Self.desk
        #expect(
            useCase.activateEnvironmentForCurrentScreens()
                == .switched(restoring: customCollection))
        #expect(preferences.storedActiveCollectionId == customCollection)

        // Undock again: the laptop's own selection comes back.
        screens.stubbedScreens = Self.laptop
        #expect(
            useCase.activateEnvironmentForCurrentScreens()
                == .switched(restoring: otherCollection))
        #expect(preferences.storedActiveCollectionId == otherCollection)
    }

    /// Detaching every display (a clamshell transition passes through
    /// this) records no phantom zero-display environment and keeps the
    /// selection alone.
    @Test func zeroScreensChangeNothing() {
        preferences.storedActiveCollectionId = customCollection
        useCase.activateEnvironmentForCurrentScreens()

        screens.stubbedScreens = []
        let change = useCase.activateEnvironmentForCurrentScreens()

        #expect(change == .unchanged)
        #expect(preferences.storedActiveCollectionId == customCollection)
        #expect(repository.storedStorage?.environments.count == 1)

        // The displays coming back is a plain re-detection, not a switch.
        screens.stubbedScreens = Self.desk
        #expect(useCase.activateEnvironmentForCurrentScreens() == .unchanged)
    }

    // MARK: - Persistence

    @Test func storedEnvironmentsSurviveARestart() {
        preferences.storedActiveCollectionId = customCollection
        useCase.activateEnvironmentForCurrentScreens()
        screens.stubbedScreens = Self.laptop
        useCase.activateEnvironmentForCurrentScreens()

        let relaunched = MonitorEnvironmentUseCase(
            screens: screens, repository: repository, preferences: preferences)

        #expect(relaunched.storedEnvironments().count == 2)
        #expect(
            relaunched.storedEnvironments().map(\.monitors.count).sorted() == [1, 2])
    }

    /// A failing save is logged and swallowed: environment switching keeps
    /// working for the rest of the run, like every other non-fatal
    /// persistence failure in the app.
    @Test func aFailingSaveDoesNotBreakSwitching() {
        preferences.storedActiveCollectionId = customCollection
        repository.saveError = StubError(message: "disk full")

        useCase.activateEnvironmentForCurrentScreens()
        screens.stubbedScreens = Self.laptop
        let change = useCase.activateEnvironmentForCurrentScreens()

        #expect(change == .switched(restoring: nil))
        #expect(repository.storedStorage == nil)
    }
}
