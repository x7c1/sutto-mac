import Foundation
import SuttoDomain
import SuttoOperations
import os

/// File-based ``SuttoOperations/SpaceCollectionRepository`` persisting to a
/// JSON file, by default under `~/Library/Application Support/Sutto/`.
///
/// Mirrors the GNOME `FileSpaceCollectionRepository`
/// (`infra/file/file-space-collection-repository.ts`): the storage document
/// is a JSON array of collections in the `RawSpaceCollection` format (the
/// synthesized `Codable` of ``SuttoDomain/SpaceCollection`` reproduces it
/// key for key — see the schema PR), and the file name is kept identical
/// (`custom-space-collections.sutto.json`, from the GNOME
/// `infra/constants.ts`) so a user can carry the file between the two apps
/// by hand. The GNOME app stores it in the extension data dir
/// (`~/.local/share/gnome-shell/extensions/<uuid>/`); Application Support
/// is the macOS analogue.
///
/// Load failures degrade to an empty list with a log line, exactly like the
/// GNOME repository: a missing file is the normal first run, and a corrupt
/// file must not brick the app (the presets remain available).
public final class FileSpaceCollectionRepository: SpaceCollectionRepository {
    /// File name shared with the GNOME version
    /// (`CUSTOM_SPACE_COLLECTIONS_FILE_NAME` in `infra/constants.ts`).
    static let customCollectionsFileName = "custom-space-collections.sutto.json"

    private let customFileURL: URL
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "persistence")

    /// - Parameter directory: the directory holding the collection files.
    ///   Injected so tests run against a temp directory instead of the real
    ///   Application Support; the app passes ``defaultDirectory()``.
    public init(directory: URL) {
        customFileURL = directory.appendingPathComponent(Self.customCollectionsFileName)
    }

    /// `~/Library/Application Support/Sutto`.
    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sutto", isDirectory: true)
    }

    public func loadCustomCollections() -> [SpaceCollection] {
        guard FileManager.default.fileExists(atPath: customFileURL.path) else {
            // First run: no file yet. Not an error.
            return []
        }
        do {
            let data = try Data(contentsOf: customFileURL)
            return try JSONDecoder().decode([SpaceCollection].self, from: data)
        } catch {
            logger.error(
                """
                failed to load collections from \
                \(self.customFileURL.path, privacy: .public): \
                \(String(describing: error), privacy: .public)
                """)
            return []
        }
    }

    public func saveCustomCollections(_ collections: [SpaceCollection]) throws {
        try FileManager.default.createDirectory(
            at: customFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        // Pretty like the GNOME `JSON.stringify(_, null, 2)` output — the
        // file is user-visible; sorted keys keep rewrites diffable.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(collections)

        // .atomic writes to a temporary file and renames it into place, so
        // a crash mid-write can never leave a truncated collections file.
        try data.write(to: customFileURL, options: .atomic)

        logger.info(
            "saved \(collections.count) custom collections to \(self.customFileURL.path, privacy: .public)"
        )
    }
}
