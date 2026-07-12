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

    /// macOS counterpart of the GSettings key `show-panel-shortcut`. GNOME
    /// stores a GTK accelerator string (e.g. `<Control>o`); macOS has no
    /// portable accelerator syntax, so the combo is stored structurally as
    /// a dictionary `{keyCode: Int, modifiers: Int}` — the virtual key code
    /// (`kVK_*` numbering) and the raw value of
    /// ``SuttoDomain/KeyCombo/Modifiers``.
    static let panelToggleShortcutKey = "panelToggleShortcut"

    private enum ShortcutField {
        static let keyCode = "keyCode"
        static let modifiers = "modifiers"
    }

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

    public func panelToggleShortcut() -> KeyCombo? {
        guard let stored = defaults.dictionary(forKey: Self.panelToggleShortcutKey) else {
            return nil
        }
        guard
            let keyCode = stored[ShortcutField.keyCode] as? Int,
            let modifiers = stored[ShortcutField.modifiers] as? Int,
            let narrowKeyCode = UInt16(exactly: keyCode),
            let narrowModifiers = UInt8(exactly: modifiers)
        else {
            // Same degradation as an invalid collection id: fall back to
            // the default with a log line instead of crashing on a
            // hand-edited or corrupted value.
            logger.error(
                "invalid panel toggle shortcut in defaults: \(String(describing: stored), privacy: .public)"
            )
            return nil
        }
        return KeyCombo(
            keyCode: narrowKeyCode,
            modifiers: KeyCombo.Modifiers(rawValue: narrowModifiers)
        )
    }

    public func setPanelToggleShortcut(_ combo: KeyCombo?) {
        if let combo {
            defaults.set(
                [
                    ShortcutField.keyCode: Int(combo.keyCode),
                    ShortcutField.modifiers: Int(combo.modifiers.rawValue),
                ],
                forKey: Self.panelToggleShortcutKey
            )
        } else {
            defaults.removeObject(forKey: Self.panelToggleShortcutKey)
        }
    }
}
