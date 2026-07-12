import Foundation
import SuttoDomain
import SuttoOperations
import Testing

@testable import SuttoInfra

/// Drives the whole import pipeline with the real infra adapters — the
/// actual GNOME sample file on disk, `LocalFileReader`, the file
/// repository over a temp directory, and a defaults-suite preferences
/// repository — proving parse → validate → convert → persist → load end to
/// end, including what a restart would see.
@Suite @MainActor struct ImportEndToEndTests {
    /// A real sample document vendored verbatim from the GNOME
    /// repository's docs/examples/ (see LayoutConfigurationCodecTests),
    /// resolved relative to `#filePath` — the unit tests always run from a
    /// source checkout.
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/SuttoInfraTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("SuttoDomainTests/Fixtures/single-wide-monitor.json")
    }

    @Test func importedFixturePersistsAcrossRepositoryInstances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuttoImportE2E-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "io.github.x7c1.SuttoMac.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        // Import through the same wiring the app composes in AppDelegate.
        let useCase = ImportCollectionUseCase(
            repository: FileSpaceCollectionRepository(directory: directory),
            fileReader: LocalFileReader()
        )
        let imported = try useCase.importCollection(at: fixtureURL).get()
        #expect(imported.name == "Single Monitor Basic")

        // Fresh instances over the same storage stand in for a restart.
        let reopenedRepository = FileSpaceCollectionRepository(directory: directory)
        let reopenedPreferences = UserDefaultsPreferencesRepository(defaults: defaults)

        let activeGroups = ActiveLayoutGroupsUseCase(
            repository: reopenedRepository,
            preferences: reopenedPreferences,
            presetGroups: BuiltInPresets.standardLayoutGroups
        )

        // Importing adds without activating (as in GNOME): the panel still
        // shows the presets until the collection is selected in settings.
        #expect(
            activeGroups.activeLayoutGroups().map(\.name)
                == BuiltInPresets.standardLayoutGroups.map(\.name))

        // Selecting the imported collection in the settings list flips the
        // panel to it: the sample's two spaces project to "half split" and
        // "full".
        let settings = CollectionSettingsUseCase(
            repository: reopenedRepository,
            preferences: reopenedPreferences
        )
        let importedEntry = try #require(
            settings.entries().first { $0.kind == .custom(imported.id) })
        settings.select(importedEntry)

        let groups = activeGroups.activeLayoutGroups()
        #expect(groups.map(\.name) == ["half split", "full"])
        #expect(groups[0].layouts.map(\.label) == ["Left", "Right"])
        #expect(groups[1].layouts.map(\.label) == ["Full"])

        // And the persisted collection is the imported one, byte-stable
        // through the storage codec.
        #expect(reopenedRepository.loadCustomCollections() == [imported])
        #expect(reopenedPreferences.activeCollectionId() == imported.id)
    }
}
