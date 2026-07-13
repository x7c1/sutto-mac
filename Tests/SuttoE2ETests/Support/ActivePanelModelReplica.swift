import Foundation
import SuttoDomain

/// Rebuilds the panel model the app under test is rendering, from the
/// outside: the same resolution chain as the app's
/// `ActivePanelModelUseCase` — the stored active collection id resolved
/// across presets and customs, falling back to the default preset — fed by
/// the app's *documented on-disk state* (the collection files under
/// `~/Library/Application Support/Sutto/` and the `activeSpaceCollectionId`
/// preference) instead of its in-process repositories.
///
/// Reading that state is what keeps the keyboard scenario's prediction
/// valid on a developer's machine, where a real selected collection —
/// not the default preset — is what the panel shows. The file names, the
/// JSON schema (the synthesized `Codable` of
/// ``SuttoDomain/SpaceCollection``), and the preference key are all part of
/// the app's documented persistence contract (they are shared with the
/// GNOME version so users can carry the files across), so this stays an
/// outside observer: no SuttoInfra/SuttoUI import, just the contract.
@MainActor
enum ActivePanelModelReplica {
    /// `CFBundleIdentifier` of the app under test — the defaults domain its
    /// preferences live in.
    private static let appBundleId = "io.github.x7c1.SuttoMac"

    /// The miniature panel model the app resolves for `screens`.
    static func panelModel(screens: [Screen]) throws -> MiniaturePanelModel {
        guard let collection = activeCollection(screens: screens) else {
            throw E2EFailure(
                """
                the app under test resolves no collection: no active \
                selection and no stored presets. The freshly launched app \
                generates presets at startup, so an empty state here means \
                the panel was read before launch or the Application \
                Support directory is not writable.
                """)
        }
        // No stored monitor environments are passed: the e2e scenarios
        // exercise collections matching the connected display count, where
        // the app renders from the live screens and its environment
        // storage (`monitors.sutto.json`) never participates.
        return MiniaturePanelModel.make(collection: collection, screens: screens)
    }

    /// `ActivePanelModelUseCase.activeCollection()`, replicated: the stored
    /// id across presets and customs, else the default preset for the
    /// current screens. Internal (not private) because the space-toggle
    /// scenario needs the ids of the collection the app shows — the raw
    /// collection, disabled spaces included, where `panelModel` filters
    /// them the way the panel does.
    static func activeCollection(screens: [Screen]) -> SpaceCollection? {
        let presets = loadCollections(named: "preset-space-collections.sutto.json")
        if let id = activeCollectionId() {
            let customs = loadCollections(named: "custom-space-collections.sutto.json")
            if let selected = (presets + customs).first(where: { $0.id == id }) {
                return selected
            }
        }
        return PresetSelection.defaultPreset(in: presets, screens: screens)
    }

    private static func activeCollectionId() -> CollectionId? {
        guard
            let stored = CFPreferencesCopyAppValue(
                "activeSpaceCollectionId" as CFString, appBundleId as CFString) as? String
        else { return nil }
        // An invalid stored id degrades to "no selection", exactly like the
        // app's preferences repository.
        return try? CollectionId(stored)
    }

    private static func loadCollections(named fileName: String) -> [SpaceCollection] {
        let fileURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sutto", isDirectory: true)
            .appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            // Missing file: the normal first run; the app treats it the
            // same way (empty list).
            return []
        }
        return (try? JSONDecoder().decode([SpaceCollection].self, from: data)) ?? []
    }
}
