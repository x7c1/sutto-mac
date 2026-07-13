import Foundation
import SuttoDomain
import Testing

@testable import SuttoInfra

/// Round-trip tests for the file-backed monitor-environment repository,
/// run against a per-test temp directory — never the real Application
/// Support.
@Suite @MainActor struct FileMonitorEnvironmentRepositoryTests {
    /// Creates a unique temp directory, hands a repository over it to
    /// `body`, and always cleans the directory up afterwards. The
    /// directory is deliberately not created up front: the repository must
    /// handle both a missing directory (first save) and a missing file
    /// (first load).
    private func withRepository(
        _ body: (FileMonitorEnvironmentRepository, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuttoInfraTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(FileMonitorEnvironmentRepository(directory: directory), directory)
    }

    private func makeStorage(collectionId: CollectionId? = nil) -> MonitorEnvironmentStorage {
        let monitors = [
            Monitor(
                index: 0,
                geometry: PixelRect(x: 0, y: 0, width: 1512, height: 982),
                workArea: PixelRect(x: 0, y: 25, width: 1512, height: 957),
                isPrimary: true
            ),
            Monitor(
                index: 1,
                geometry: PixelRect(x: 1512, y: 0, width: 3440, height: 1440),
                workArea: PixelRect(x: 1512, y: 0, width: 3440, height: 1440),
                isPrimary: false
            ),
        ]
        let id = MonitorEnvironmentId.generate(for: monitors)
        return MonitorEnvironmentStorage(
            environments: [
                MonitorEnvironment(
                    id: id,
                    monitors: monitors,
                    lastActiveCollectionId: collectionId,
                    // Exactly representable in binary (…000.5 s), so the
                    // seconds↔milliseconds conversion round-trips the Date
                    // bit for bit and the equality checks below hold.
                    lastActiveAt: Date(timeIntervalSince1970: 1_700_000_000.5)
                )
            ],
            currentId: id
        )
    }

    @Test func roundTripsTheStorage() throws {
        try withRepository { repository, _ in
            let storage = makeStorage(collectionId: .generate())

            try repository.save(storage)

            #expect(repository.load() == storage)
        }
    }

    @Test func roundTripsAnEnvironmentWithoutASelection() throws {
        try withRepository { repository, _ in
            let storage = makeStorage(collectionId: nil)

            try repository.save(storage)

            #expect(repository.load()?.environments.first?.lastActiveCollectionId == nil)
        }
    }

    /// First run: no file yet. `nil`, not an error.
    @Test func loadsNilWhenNoFileExists() throws {
        try withRepository { repository, _ in
            #expect(repository.load() == nil)
        }
    }

    /// A corrupt file degrades to `nil` with a log line — environment
    /// memory is reconstructible and must never brick the app.
    @Test func loadsNilFromACorruptFile() throws {
        try withRepository { repository, directory in
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(
                to: directory.appendingPathComponent("monitors.sutto.json"))

            #expect(repository.load() == nil)
        }
    }

    /// An invalid collection id inside an otherwise valid file degrades to
    /// "no selection" for that environment, like the GNOME
    /// `parseCollectionId` — one bad value must not drop the whole file.
    @Test func anInvalidCollectionIdDegradesToNoSelection() throws {
        try withRepository { repository, directory in
            var storage = makeStorage(collectionId: .generate())
            try repository.save(storage)

            let fileURL = directory.appendingPathComponent("monitors.sutto.json")
            let json = try String(contentsOf: fileURL, encoding: .utf8)
                .replacingOccurrences(
                    of: storage.environments[0].lastActiveCollectionId!.description,
                    with: "not-a-uuid")
            try Data(json.utf8).write(to: fileURL)

            storage.environments[0].lastActiveCollectionId = nil
            #expect(repository.load() == storage)
        }
    }

    /// The file shape is the GNOME `monitors.sutto.json` format: the same
    /// keys, `lastActiveCollectionId` as an empty string for none, and
    /// `lastActiveAt` in milliseconds since the epoch.
    @Test func writesTheGnomeFileShape() throws {
        try withRepository { repository, directory in
            try repository.save(makeStorage(collectionId: nil))

            let data = try Data(
                contentsOf: directory.appendingPathComponent("monitors.sutto.json"))
            let root = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(Set(root.keys) == ["environments", "current"])

            let environment = try #require(
                (root["environments"] as? [[String: Any]])?.first)
            #expect(
                Set(environment.keys)
                    == ["id", "monitors", "lastActiveCollectionId", "lastActiveAt"])
            #expect(environment["lastActiveCollectionId"] as? String == "")
            #expect(environment["lastActiveAt"] as? Double == 1_700_000_000_500)

            let monitor = try #require((environment["monitors"] as? [[String: Any]])?.first)
            #expect(Set(monitor.keys) == ["index", "geometry", "workArea", "isPrimary"])
            #expect(
                Set(try #require(monitor["geometry"] as? [String: Any]).keys)
                    == ["x", "y", "width", "height"])
        }
    }
}
