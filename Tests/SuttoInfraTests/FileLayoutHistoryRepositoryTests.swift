import Foundation
import SuttoDomain
import Testing

@testable import SuttoInfra

/// Round-trip tests for the file-backed layout-history repository, run
/// against a per-test temp directory — never the real Application Support.
@Suite @MainActor struct FileLayoutHistoryRepositoryTests {
    /// Creates a unique temp directory, hands a repository over it to
    /// `body`, and always cleans the directory up afterwards. The directory
    /// is deliberately not created up front: the repository must handle both
    /// a missing directory (first save) and a missing file (first load).
    private func withRepository(
        _ body: (FileLayoutHistoryRepository, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuttoInfraTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(FileLayoutHistoryRepository(directory: directory), directory)
    }

    /// A small history of distinct, already-compact events in oldest-first
    /// order, so a load that re-compacts leaves it unchanged and the
    /// equality checks hold. Integer-second timestamps are exactly
    /// representable, so the seconds↔milliseconds conversion round-trips the
    /// dates bit for bit.
    private func makeHistory() -> LayoutHistory {
        LayoutHistory(events: [
            LayoutHistoryEvent(
                collectionId: .generate(),
                bundleHash: "0123456789abcdef",
                titleHash: "fedcba9876543210",
                layoutId: .generate(),
                lastAppliedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            LayoutHistoryEvent(
                collectionId: .generate(),
                bundleHash: "0123456789abcdef",
                titleHash: "00112233445566aa",
                layoutId: .generate(),
                lastAppliedAt: Date(timeIntervalSince1970: 1_700_000_100)
            ),
        ])
    }

    private var fileURL: (URL) -> URL {
        { $0.appendingPathComponent("layout-history.sutto.json") }
    }

    @Test func roundTripsTheHistory() throws {
        try withRepository { repository, _ in
            let history = makeHistory()

            try repository.save(history)

            #expect(repository.load() == history)
        }
    }

    @Test func roundTripsAnEmptyHistory() throws {
        try withRepository { repository, _ in
            try repository.save(LayoutHistory())

            #expect(repository.load() == LayoutHistory())
        }
    }

    /// First run: no file yet. An empty history, not an error.
    @Test func loadsEmptyWhenNoFileExists() throws {
        try withRepository { repository, _ in
            #expect(repository.load() == LayoutHistory())
        }
    }

    /// A corrupt file degrades to an empty history with a log line —
    /// recommendations are a convenience and must never brick the app.
    @Test func loadsEmptyFromACorruptFile() throws {
        try withRepository { repository, directory in
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: fileURL(directory))

            #expect(repository.load() == LayoutHistory())
        }
    }

    /// A record with an unparsable id inside an otherwise valid file is
    /// dropped, like the GNOME `parseCollectionId` — one bad record must not
    /// discard the whole file. The valid record survives.
    @Test func dropsRecordsWithInvalidIds() throws {
        try withRepository { repository, directory in
            let history = makeHistory()
            try repository.save(history)

            let url = fileURL(directory)
            let json = try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(
                    of: history.events[0].collectionId.description,
                    with: "not-a-uuid")
            try Data(json.utf8).write(to: url)

            let loaded = repository.load()
            #expect(loaded.events.count == 1)
            #expect(loaded.events.first?.titleHash == "00112233445566aa")
        }
    }

    /// `.sortedKeys` makes the output deterministic: the same history writes
    /// byte-identical files, and each record's keys are the fixed set.
    @Test func writesDeterministicSortedOutput() throws {
        try withRepository { repository, directory in
            let history = makeHistory()

            try repository.save(history)
            let first = try Data(contentsOf: fileURL(directory))
            try repository.save(history)
            let second = try Data(contentsOf: fileURL(directory))
            #expect(first == second)

            let root = try #require(
                try JSONSerialization.jsonObject(with: first) as? [String: Any])
            #expect(Set(root.keys) == ["records"])

            let record = try #require((root["records"] as? [[String: Any]])?.first)
            #expect(
                Set(record.keys)
                    == ["collectionId", "bundleHash", "titleHash", "layoutId", "lastAppliedAt"])
        }
    }
}
