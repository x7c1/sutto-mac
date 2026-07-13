import Foundation
import SuttoDomain
import SuttoOperations
import os

/// File-based ``SuttoOperations/MonitorEnvironmentRepository`` persisting
/// to a JSON file, by default next to the collection files under
/// `~/Library/Application Support/Sutto/`.
///
/// Mirrors the GNOME `FileMonitorEnvironmentRepository`
/// (`infra/file/file-monitor-environment-repository.ts`) and its
/// serialization (`infra/file/raw-monitor-environment-storage.ts`): the
/// same file name (`monitors.sutto.json`, from the GNOME
/// `infra/constants.ts`) and the same JSON shape — environments carrying
/// `id`, `monitors` (with `geometry`, `workArea`, `isPrimary`),
/// `lastActiveCollectionId` (empty string for none), and `lastActiveAt`
/// (milliseconds since the epoch), plus the `current` environment id.
/// Unlike the collection files the *contents* are not portable across the
/// two apps — the records describe the machine's own displays — but the
/// shared shape keeps the two codebases recognizable.
///
/// A missing file is the normal first run and a corrupt one degrades to
/// `nil` with a log line, exactly like the GNOME `load()`: environment
/// memory is reconstructible, so it must never brick the app.
public final class FileMonitorEnvironmentRepository: MonitorEnvironmentRepository {
    /// File name shared with the GNOME version (`MONITORS_FILE_NAME`).
    static let fileName = "monitors.sutto.json"

    private let fileURL: URL
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "persistence")

    /// - Parameter directory: the directory holding the file. Injected so
    ///   tests run against a temp directory instead of the real
    ///   Application Support; the app passes
    ///   `FileSpaceCollectionRepository.defaultDirectory()`.
    public init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName)
    }

    public func load() -> MonitorEnvironmentStorage? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // First run: no file yet. Not an error.
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let raw = try JSONDecoder().decode(RawMonitorEnvironmentStorage.self, from: data)
            return raw.storage(reportingInvalidCollectionId: { value in
                // GNOME parity (`parseCollectionId`): an invalid stored id
                // degrades to "no selection" with a log line.
                self.logger.error(
                    "invalid collection id in monitor environments: \(value, privacy: .public)")
            })
        } catch {
            logger.error(
                """
                failed to load monitor environments from \
                \(self.fileURL.path, privacy: .public): \
                \(String(describing: error), privacy: .public)
                """)
            return nil
        }
    }

    public func save(_ storage: MonitorEnvironmentStorage) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        // Pretty like the GNOME `JSON.stringify(_, null, 2)` output — the
        // file is user-visible; sorted keys keep rewrites diffable.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(RawMonitorEnvironmentStorage(storage))

        // .atomic writes to a temporary file and renames it into place, so
        // a crash mid-write can never leave a truncated file.
        try data.write(to: fileURL, options: .atomic)

        logger.info(
            "saved \(storage.environments.count) monitor environments to \(self.fileURL.path, privacy: .public)"
        )
    }
}

// MARK: - Raw JSON format

/// The on-disk shape, mirroring `RawMonitorEnvironmentStorage` in the GNOME
/// `infra/file/raw-monitor-environment-storage.ts` key for key.
private struct RawMonitorEnvironmentStorage: Codable {
    struct Environment: Codable {
        let id: String
        let monitors: [RawMonitor]
        /// Empty string when no collection was recorded — the GNOME
        /// serializer writes `''` for `null`.
        let lastActiveCollectionId: String
        /// Milliseconds since the epoch (`Date.now()` in the original).
        let lastActiveAt: Double
    }

    struct RawMonitor: Codable {
        struct Rect: Codable {
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }

        let index: Int
        let geometry: Rect
        let workArea: Rect
        let isPrimary: Bool
    }

    let environments: [Environment]
    let current: String

    init(_ storage: MonitorEnvironmentStorage) {
        environments = storage.environments.map { environment in
            Environment(
                id: environment.id,
                monitors: environment.monitors.map { monitor in
                    RawMonitor(
                        index: monitor.index,
                        geometry: RawMonitor.Rect(monitor.geometry),
                        workArea: RawMonitor.Rect(monitor.workArea),
                        isPrimary: monitor.isPrimary
                    )
                },
                lastActiveCollectionId: environment.lastActiveCollectionId?.description ?? "",
                lastActiveAt: environment.lastActiveAt.timeIntervalSince1970 * 1000
            )
        }
        current = storage.currentId
    }

    /// The domain storage, reporting (and dropping) invalid collection id
    /// strings through `reportingInvalidCollectionId`.
    func storage(
        reportingInvalidCollectionId report: (String) -> Void
    ) -> MonitorEnvironmentStorage {
        MonitorEnvironmentStorage(
            environments: environments.map { environment in
                MonitorEnvironment(
                    id: environment.id,
                    monitors: environment.monitors.map { monitor in
                        Monitor(
                            index: monitor.index,
                            geometry: monitor.geometry.pixelRect,
                            workArea: monitor.workArea.pixelRect,
                            isPrimary: monitor.isPrimary
                        )
                    },
                    lastActiveCollectionId: parseCollectionId(
                        environment.lastActiveCollectionId, reporting: report),
                    lastActiveAt: Date(timeIntervalSince1970: environment.lastActiveAt / 1000)
                )
            },
            currentId: current
        )
    }

    private func parseCollectionId(
        _ value: String, reporting report: (String) -> Void
    ) -> CollectionId? {
        guard !value.isEmpty else { return nil }
        guard let id = try? CollectionId(value) else {
            report(value)
            return nil
        }
        return id
    }
}

extension RawMonitorEnvironmentStorage.RawMonitor.Rect {
    fileprivate init(_ rect: PixelRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    fileprivate var pixelRect: PixelRect {
        PixelRect(x: x, y: y, width: width, height: height)
    }
}
