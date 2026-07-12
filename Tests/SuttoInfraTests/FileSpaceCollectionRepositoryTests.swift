import Foundation
import SuttoDomain
import Testing

@testable import SuttoInfra

/// Round-trip tests for the file-backed repository, run against a
/// per-test temp directory — never the real Application Support.
@Suite @MainActor struct FileSpaceCollectionRepositoryTests {
    /// Creates a unique temp directory, hands a repository over it to
    /// `body`, and always cleans the directory up afterwards.
    private func withRepository(
        _ body: (FileSpaceCollectionRepository, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuttoInfraTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // The directory is deliberately not created here: the repository
        // must handle both a missing directory (first save) and a missing
        // file (first load).
        try body(FileSpaceCollectionRepository(directory: directory), directory)
    }

    private func makeCollection(name: String) -> SpaceCollection {
        SpaceCollection(
            id: .generate(),
            name: name,
            rows: [
                SpacesRow(spaces: [
                    Space(
                        id: .generate(),
                        enabled: true,
                        displays: [
                            "0": LayoutGroup(
                                name: "half split",
                                layouts: [
                                    Layout(
                                        label: "Left",
                                        position: LayoutPosition(x: "0", y: "0"),
                                        size: LayoutSize(width: "50%", height: "100%")
                                    )
                                ]
                            )
                        ]
                    )
                ])
            ]
        )
    }

    /// First run: no file yet — an empty list, not an error.
    @Test func loadingWithoutAFileYieldsNothing() throws {
        try withRepository { repository, _ in
            #expect(repository.loadCustomCollections().isEmpty)
        }
    }

    /// Saving creates the directory on demand and a reload returns the
    /// identical hierarchy.
    @Test func savedCollectionsRoundTrip() throws {
        try withRepository { repository, _ in
            let collections = [makeCollection(name: "Work"), makeCollection(name: "Home")]

            try repository.saveCustomCollections(collections)

            #expect(repository.loadCustomCollections() == collections)
        }
    }

    /// A separate instance over the same directory sees the saved data —
    /// what "persists across restarts" means at this layer.
    @Test func aFreshInstanceLoadsWhatWasSaved() throws {
        try withRepository { repository, directory in
            let collections = [makeCollection(name: "Work")]
            try repository.saveCustomCollections(collections)

            let reopened = FileSpaceCollectionRepository(directory: directory)

            #expect(reopened.loadCustomCollections() == collections)
        }
    }

    @Test func addCustomCollectionAppendsAndPersists() throws {
        try withRepository { repository, directory in
            let existing = makeCollection(name: "Existing")
            try repository.saveCustomCollections([existing])

            let added = try repository.addCustomCollection(
                name: "Imported", rows: makeCollection(name: "ignored").rows)

            #expect(added.name == "Imported")
            let reopened = FileSpaceCollectionRepository(directory: directory)
            #expect(reopened.loadCustomCollections() == [existing, added])
        }
    }

    /// Two added collections get distinct minted ids.
    @Test func addCustomCollectionMintsDistinctIds() throws {
        try withRepository { repository, _ in
            let first = try repository.addCustomCollection(name: "One", rows: [])
            let second = try repository.addCustomCollection(name: "Two", rows: [])

            #expect(first.id != second.id)
        }
    }

    /// A corrupt file degrades to an empty list (GNOME parity: log and
    /// return []) so the app still starts and falls back to presets.
    @Test func aCorruptFileDegradesToNothing() throws {
        try withRepository { repository, directory in
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(
                FileSpaceCollectionRepository.customCollectionsFileName)
            try Data("not json at all {".utf8).write(to: file)

            #expect(repository.loadCustomCollections().isEmpty)
        }
    }

    /// The storage document is the GNOME storage format: a JSON *array* of
    /// collections, each in the `RawSpaceCollection` shape.
    @Test func storesAJSONArrayOfCollections() throws {
        try withRepository { repository, directory in
            try repository.saveCustomCollections([makeCollection(name: "Work")])

            let file = directory.appendingPathComponent(
                FileSpaceCollectionRepository.customCollectionsFileName)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))

            let array = try #require(object as? [[String: Any]])
            #expect(array.count == 1)
            #expect(array[0]["name"] as? String == "Work")
            #expect(array[0]["id"] is String)
            #expect(array[0]["rows"] is [Any])
        }
    }
}
