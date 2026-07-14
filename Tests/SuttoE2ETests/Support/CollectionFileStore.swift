import Foundation
import SuttoDomain

/// Rewrites a space's enabled flag directly in the app's collection files,
/// through the documented persistence contract (the same file names,
/// schema, and formatting the app writes).
///
/// This is the safety net of the space-toggle scenario: the app under test
/// runs against the developer's *real* collection files, so a scenario
/// that dies between toggling a space off and back on would leave the
/// developer's panel missing a space. The scenario's cleanup restores the
/// original flag here, whether or not the app is still running — the app
/// re-reads the files on every access, so the restoration is picked up on
/// the next panel open.
@MainActor
enum CollectionFileStore {
    /// Both storage documents, presets first — the order the app itself
    /// searches (`updateSpaceEnabled` in the repository).
    private static let fileNames = [
        "preset-space-collections.sutto.json",
        "custom-space-collections.sutto.json",
    ]

    /// Sets the space's enabled flag in whichever file holds the
    /// collection. Quietly does nothing when the collection or space no
    /// longer exists — cleanup must not add its own failure on top of the
    /// scenario's.
    static func restoreSpaceEnabled(
        collectionId: CollectionId, spaceId: SpaceId, enabled: Bool
    ) {
        for fileURL in fileNames.map(url(for:)) {
            guard
                let data = try? Data(contentsOf: fileURL),
                var collections = try? JSONDecoder().decode([SpaceCollection].self, from: data),
                let index = collections.firstIndex(where: { $0.id == collectionId }),
                let updated = collections[index].updatingSpace(spaceId, enabled: enabled)
            else { continue }
            collections[index] = updated

            let encoder = JSONEncoder()
            // The app's own formatting (pretty, sorted keys), so the
            // restoration does not reformat the developer's file.
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let encoded = try? encoder.encode(collections) {
                try? encoded.write(to: fileURL, options: .atomic)
            }
            return
        }
    }

    private static func url(for fileName: String) -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sutto", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
