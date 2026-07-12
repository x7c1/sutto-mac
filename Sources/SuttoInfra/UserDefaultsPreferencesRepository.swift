import Foundation
import SuttoDomain
import SuttoOperations
import os

/// `UserDefaults`-backed ``SuttoOperations/PreferencesRepository``.
///
/// The GNOME version stores the active collection id in GSettings under
/// `active-space-collection-id` (`infra/glib/preferences-repository.ts`)
/// while the collections themselves live in JSON files. `UserDefaults` is
/// the macOS analogue of GSettings for small keyed preferences, so this
/// keeps the same storage split; the key name is the camel-cased form of
/// the GSettings key.
public final class UserDefaultsPreferencesRepository: PreferencesRepository {
    /// macOS counterpart of the GSettings key `active-space-collection-id`.
    static let activeCollectionIdKey = "activeSpaceCollectionId"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "persistence")

    /// - Parameter defaults: injected so tests use an isolated suite
    ///   instead of the app's real defaults.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func activeCollectionId() -> CollectionId? {
        guard let stored = defaults.string(forKey: Self.activeCollectionIdKey), !stored.isEmpty
        else {
            return nil
        }
        do {
            return try CollectionId(stored)
        } catch {
            // GNOME parity: an invalid stored id degrades to "no selection"
            // with a log line (getActiveCollectionId catches and logs too).
            logger.error(
                "invalid active collection id in defaults: \(stored, privacy: .public)")
            return nil
        }
    }

    public func setActiveCollectionId(_ id: CollectionId?) {
        if let id {
            defaults.set(id.description, forKey: Self.activeCollectionIdKey)
        } else {
            defaults.removeObject(forKey: Self.activeCollectionIdKey)
        }
    }
}
