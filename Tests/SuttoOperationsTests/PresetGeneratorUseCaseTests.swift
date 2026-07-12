import SuttoDomain
import Testing

@testable import SuttoOperations

@Suite @MainActor struct PresetGeneratorUseCaseTests {
    private let repository = InMemorySpaceCollectionRepository()
    private let screens = StubScreenProvider(screens: [
        StubScreenProvider.screen(width: 1920, height: 1080)
    ])

    private func makeUseCase() -> PresetGeneratorUseCase {
        PresetGeneratorUseCase(repository: repository, screens: screens)
    }

    /// First ensure: both flavors for the current monitor count are
    /// generated and persisted, standard first (the GNOME iteration order,
    /// which also makes it the `presets[0]` fallback).
    @Test func generatesBothPresetFlavorsForTheCurrentMonitors() {
        makeUseCase().ensurePresetsForCurrentMonitors()

        #expect(
            repository.presetCollections.map(\.name) == [
                "1 Monitor - Standard",
                "1 Monitor - Wide",
            ])
    }

    /// The generated presets carry the monitor count into their structure:
    /// every space assigns a group to every monitor.
    @Test func generatesPresetsSizedToTheMonitorCount() {
        screens.stubbedScreens = [
            StubScreenProvider.screen(width: 1920, height: 1080),
            StubScreenProvider.screen(width: 2560, height: 1440),
        ]

        makeUseCase().ensurePresetsForCurrentMonitors()

        #expect(
            repository.presetCollections.map(\.name) == [
                "2 Monitors - Standard",
                "2 Monitors - Wide",
            ])
        for space in repository.presetCollections.flatMap({ $0.rows.flatMap(\.spaces) }) {
            #expect(space.displays.keys.sorted() == ["0", "1"])
        }
    }

    /// A second ensure with the same monitors changes nothing: existing
    /// presets are matched by name and never regenerated, so their ids
    /// survive across launches.
    @Test func ensureIsIdempotent() {
        let useCase = makeUseCase()
        useCase.ensurePresetsForCurrentMonitors()
        let first = repository.presetCollections

        useCase.ensurePresetsForCurrentMonitors()

        #expect(repository.presetCollections == first)
    }

    /// A new monitor count appends its presets while keeping the earlier
    /// ones (the file accumulates configurations, like the GNOME preset
    /// file).
    @Test func aNewMonitorCountAppendsWithoutDroppingEarlierPresets() {
        let useCase = makeUseCase()
        useCase.ensurePresetsForCurrentMonitors()

        screens.stubbedScreens = [
            StubScreenProvider.screen(width: 1920, height: 1080),
            StubScreenProvider.screen(width: 1920, height: 1080),
        ]
        useCase.ensurePresetsForCurrentMonitors()

        #expect(
            repository.presetCollections.map(\.name) == [
                "1 Monitor - Standard",
                "1 Monitor - Wide",
                "2 Monitors - Standard",
                "2 Monitors - Wide",
            ])
    }

    /// No monitors, no generation — the GNOME zero-count guard.
    @Test func skipsGenerationWithoutScreens() {
        screens.stubbedScreens = []

        makeUseCase().ensurePresetsForCurrentMonitors()

        #expect(repository.presetCollections.isEmpty)
    }

    /// A failing save is logged, not thrown: launch and panel-open paths
    /// call this and must not crash over a read-only disk.
    @Test func aFailingSaveDoesNotThrow() {
        repository.saveError = StubError(message: "disk full")

        makeUseCase().ensurePresetsForCurrentMonitors()

        #expect(repository.presetCollections.isEmpty)
    }
}
