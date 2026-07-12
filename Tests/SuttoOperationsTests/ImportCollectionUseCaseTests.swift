import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

@Suite @MainActor struct ImportCollectionUseCaseTests {
    private let repository = InMemorySpaceCollectionRepository()
    private let preferences = InMemoryPreferencesRepository()

    private func makeUseCase(reader: StubFileReader) -> ImportCollectionUseCase {
        ImportCollectionUseCase(
            repository: repository,
            preferences: preferences,
            fileReader: reader
        )
    }

    private func importJSON(_ json: String) -> Result<SpaceCollection, LayoutImportError> {
        makeUseCase(reader: StubFileReader(json: json))
            .importCollection(at: URL(fileURLWithPath: "/stub/layouts.json"))
    }

    private let validJSON = """
        {
          "name": "Imported",
          "layoutGroups": [
            {
              "name": "half split",
              "layouts": [
                { "label": "Left", "x": "0", "y": "0", "width": "50%", "height": "100%" }
              ]
            }
          ],
          "rows": [
            { "spaces": [{ "displays": { "0": "half split" } }] }
          ]
        }
        """

    // MARK: - Success path

    @Test func importsAValidConfiguration() throws {
        let collection = try importJSON(validJSON).get()

        #expect(collection.name == "Imported")
        #expect(collection.rows.count == 1)
        #expect(collection.rows[0].spaces[0].displays["0"]?.name == "half split")
    }

    @Test func persistsTheImportedCollection() throws {
        let collection = try importJSON(validJSON).get()

        #expect(repository.collections == [collection])
    }

    /// Importing selects the new collection so the panel shows it right
    /// away — a deliberate deviation from GNOME (which leaves selection to
    /// its preferences UI) until the settings screen lands in the next PR.
    @Test func makesTheImportedCollectionActive() throws {
        let collection = try importJSON(validJSON).get()

        #expect(preferences.storedActiveCollectionId == collection.id)
    }

    @Test func appendsToExistingCollections() throws {
        let existing = try repository.addCustomCollection(name: "Existing", rows: [])

        let imported = try importJSON(validJSON).get()

        #expect(repository.collections == [existing, imported])
    }

    // MARK: - Failure paths

    @Test func reportsAnUnreadableFile() {
        let useCase = makeUseCase(
            reader: StubFileReader(error: StubError(message: "permission denied")))

        let result = useCase.importCollection(at: URL(fileURLWithPath: "/stub/layouts.json"))

        #expect(result == .failure(.unreadableFile(reason: "permission denied")))
    }

    @Test func reportsMalformedJSON() {
        let result = importJSON("this is not JSON {")

        guard case .failure(.invalidJSON) = result else {
            Issue.record("expected .invalidJSON, got \(result)")
            return
        }
    }

    /// Well-formed JSON of the wrong shape is a configuration problem, not
    /// a JSON problem, and the reason names the offending field.
    @Test func reportsAMissingField() {
        let result = importJSON(#"{"name": "Broken", "rows": []}"#)

        #expect(
            result
                == .failure(.invalidConfiguration(reason: "Missing field \"layoutGroups\".")))
    }

    @Test func reportsATypeMismatchWithItsPath() {
        let result = importJSON(
            #"{"name": "Broken", "layoutGroups": [{"name": "g", "layouts": "oops"}], "rows": []}"#)

        #expect(
            result
                == .failure(
                    .invalidConfiguration(
                        reason: "Unexpected value type at \"layoutGroups[0].layouts\".")))
    }

    /// The empty-name rejection from `isValidLayoutConfiguration` — the
    /// semantic rule deferred out of the schema PR.
    @Test(arguments: ["\"\"", "\"   \""])
    func rejectsAnEmptyOrWhitespaceName(nameJSON: String) {
        let result = importJSON(#"{"name": \#(nameJSON), "layoutGroups": [], "rows": []}"#)

        guard case .failure(.invalidConfiguration(let reason)) = result else {
            Issue.record("expected .invalidConfiguration, got \(result)")
            return
        }
        #expect(reason.contains("name"))
    }

    @Test func reportsASaveFailure() {
        repository.saveError = StubError(message: "disk full")

        let result = importJSON(validJSON)

        #expect(result == .failure(.saveFailed(reason: "disk full")))
    }

    @Test func failedImportsLeaveNoTrace() {
        repository.saveError = StubError(message: "disk full")

        _ = importJSON(validJSON)

        #expect(repository.collections.isEmpty)
        #expect(preferences.storedActiveCollectionId == nil)
    }

    /// Unknown group references degrade to a partial import (log-and-skip),
    /// exactly like the GNOME importer — the import itself still succeeds.
    @Test func importsDespiteUnknownGroupReferences() throws {
        let json = """
            {
              "name": "Partial",
              "layoutGroups": [],
              "rows": [{ "spaces": [{ "displays": { "0": "missing group" } }] }]
            }
            """

        let collection = try importJSON(json).get()

        #expect(collection.rows[0].spaces[0].displays.isEmpty)
    }

    // MARK: - Real GNOME sample document

    /// Feeds a real fixture (vendored verbatim from the GNOME repository's
    /// docs/examples/, see LayoutConfigurationCodecTests) through the whole
    /// use case. The fixture lives in the SuttoDomainTests resources;
    /// resolving it relative to `#filePath` works because the unit tests
    /// always run from a source checkout.
    @Test func importsARealGnomeSampleDocument() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/SuttoOperationsTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("SuttoDomainTests/Fixtures/single-wide-monitor.json")
        let data = try Data(contentsOf: fixtureURL)

        let useCase = makeUseCase(reader: StubFileReader(data: data))
        let collection = try useCase.importCollection(at: fixtureURL).get()

        #expect(collection.name == "Single Monitor Basic")
        #expect(repository.collections == [collection])
        #expect(preferences.storedActiveCollectionId == collection.id)

        // The imported collection projects onto the panel as the sample's
        // two spaces: "half split" and "full".
        let groups = LayoutPanelProjection.layoutGroups(in: collection)
        #expect(groups.map(\.name) == ["half split", "full"])
        #expect(groups[0].layouts.map(\.label) == ["Left", "Right"])
        #expect(groups[1].layouts.map(\.label) == ["Full"])
    }
}
