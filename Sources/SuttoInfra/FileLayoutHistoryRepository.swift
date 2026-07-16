import Foundation
import SuttoDomain
import SuttoOperations
import os

/// File-based ``SuttoOperations/LayoutHistoryRepository`` persisting the
/// learned layout history to a JSON file, by default next to the collection
/// files under `~/Library/Application Support/Sutto/`.
///
/// Mirrors the GNOME `FileLayoutHistoryRepository`
/// (`infra/file/file-layout-history-repository.ts`) in intent, but not in
/// storage mechanics. The GNOME version appends events to a JSONL log and
/// compacts lazily; this port keeps the domain
/// (``SuttoDomain/LayoutHistory``) in a permanently compacted form and
/// rewrites the whole file each save — the same `RawXxx` + `.atomic`
/// full-write + degrade-on-corruption shape as
/// ``FileMonitorEnvironmentRepository``. The record count is tiny (apps ×
/// `maxLayoutsPerApp`), so a full rewrite costs nothing and there is no
/// second compaction path to keep in sync (see the v0.5 design, decision
/// #5).
///
/// Each record stores *hashes* of the bundle identifier and window title,
/// never the raw strings, so the file never leaks which apps the user runs
/// or what their windows are titled (the GNOME privacy design). A missing
/// file is the normal first run and a corrupt one degrades to an empty
/// history with a log line: recommendations are a convenience and must never
/// brick the app.
public final class FileLayoutHistoryRepository: LayoutHistoryRepository {
    /// File name, following the `<name>.sutto.json` convention of the other
    /// persisted files under the same directory.
    static let fileName = "layout-history.sutto.json"

    private let fileURL: URL
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "persistence")

    /// - Parameter directory: the directory holding the file. Injected so
    ///   tests run against a temp directory instead of the real
    ///   Application Support; the app passes
    ///   `FileSpaceCollectionRepository.defaultDirectory()`.
    public init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName)
    }

    public func load() -> LayoutHistory {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // First run: no file yet. Not an error.
            return LayoutHistory()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let raw = try JSONDecoder().decode(RawLayoutHistory.self, from: data)
            return raw.history(reportingInvalidRecord: { reason in
                // An individual record with an unparsable id degrades to
                // "dropped" with a log line, like the GNOME
                // `parseCollectionId` — one bad record must not discard the
                // whole file. `LayoutHistory` re-compacts the survivors.
                self.logger.error(
                    "dropping invalid layout-history record: \(reason, privacy: .public)")
            })
        } catch {
            logger.error(
                """
                failed to load layout history from \
                \(self.fileURL.path, privacy: .public): \
                \(String(describing: error), privacy: .public)
                """)
            return LayoutHistory()
        }
    }

    public func save(_ history: LayoutHistory) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        // Pretty like the other persisted files; sorted keys keep rewrites
        // diffable and the output deterministic for a given history.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // `history.events` is already compact and oldest-first, so this
        // writes the current state verbatim — no second compaction.
        let data = try encoder.encode(RawLayoutHistory(history))

        // .atomic writes to a temporary file and renames it into place, so
        // a crash mid-write can never leave a truncated history file.
        try data.write(to: fileURL, options: .atomic)

        logger.info(
            "saved \(history.events.count) layout-history records to \(self.fileURL.path, privacy: .public)"
        )
    }
}

// MARK: - Raw JSON format

/// The on-disk shape: a `records` array of hashed selections. The bundle
/// identifier and window title are stored only as hashes (``bundleHash`` /
/// ``titleHash``), and `collectionId` / `layoutId` as their canonical UUID
/// strings, matching how the collection files serialize those ids.
private struct RawLayoutHistory: Codable {
    struct Record: Codable {
        let collectionId: String
        let bundleHash: String
        let titleHash: String
        let layoutId: String
        /// Milliseconds since the epoch, matching
        /// ``RawMonitorEnvironmentStorage`` and the GNOME numeric timestamp.
        let lastAppliedAt: Double
    }

    let records: [Record]

    init(_ history: LayoutHistory) {
        records = history.events.map { event in
            Record(
                collectionId: event.collectionId.description,
                bundleHash: event.bundleHash,
                titleHash: event.titleHash,
                layoutId: event.layoutId.description,
                lastAppliedAt: event.lastAppliedAt.timeIntervalSince1970 * 1000
            )
        }
    }

    /// The domain history, dropping (and reporting) records whose ids do not
    /// parse. ``LayoutHistory`` re-compacts and re-sorts the survivors.
    func history(reportingInvalidRecord report: (String) -> Void) -> LayoutHistory {
        let events = records.compactMap { record -> LayoutHistoryEvent? in
            guard let collectionId = try? CollectionId(record.collectionId) else {
                report("invalid collection id \(record.collectionId)")
                return nil
            }
            guard let layoutId = try? LayoutId(record.layoutId) else {
                report("invalid layout id \(record.layoutId)")
                return nil
            }
            return LayoutHistoryEvent(
                collectionId: collectionId,
                bundleHash: record.bundleHash,
                titleHash: record.titleHash,
                layoutId: layoutId,
                lastAppliedAt: Date(timeIntervalSince1970: record.lastAppliedAt / 1000)
            )
        }
        return LayoutHistory(events: events)
    }
}
