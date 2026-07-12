import SuttoDomain
import os

/// Owns the global panel-toggle shortcut across its whole lifecycle:
/// resolving the effective combo (captured or default), registering it at
/// launch, and re-registering live when the user captures a new one in
/// Settings.
///
/// The GNOME counterpart splits this between its
/// `KeyboardShortcutManager` and GSettings change signals; Carbon hotkeys
/// have no equivalent of a settings-bound keybinding, so this use case does
/// the re-registration explicitly: unregister the old combo, register the
/// new one, persist. When the system refuses the new combo (typically
/// another app holds it), the old registration is restored and the error is
/// rethrown for the settings UI to present — the running shortcut is never
/// silently lost.
@MainActor
public final class PanelShortcutUseCase {
    private let preferences: any PreferencesRepository
    private let registrar: any HotKeyRegistering
    private let onPress: @MainActor () -> Void
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "shortcut")

    public init(
        preferences: any PreferencesRepository,
        registrar: any HotKeyRegistering,
        onPress: @escaping @MainActor () -> Void
    ) {
        self.preferences = preferences
        self.registrar = registrar
        self.onPress = onPress
    }

    /// The combo currently in effect: the captured one, or the built-in
    /// default when none was captured.
    public func currentCombo() -> KeyCombo {
        preferences.panelToggleShortcut() ?? .defaultTogglePanel
    }

    /// Whether the effective combo is the built-in default (the settings
    /// Reset button disables itself in that state).
    public func isDefault() -> Bool {
        currentCombo() == .defaultTogglePanel
    }

    /// Registers the effective combo. Called once at launch.
    public func registerCurrent() throws {
        let combo = currentCombo()
        try registrar.register(combo, onPress: onPress)
        logger.info("global shortcut registered: \(combo.displayString, privacy: .public)")
    }

    /// Switches the live registration to `combo` and persists it. On
    /// failure the previous combo is re-registered and nothing is stored.
    public func update(to combo: KeyCombo) throws {
        let previous = currentCombo()
        guard combo != previous else { return }

        registrar.unregisterAll()
        do {
            try registrar.register(combo, onPress: onPress)
        } catch {
            // Restore the previous registration so a refused combo does not
            // leave the app without any working shortcut. If even that
            // fails, the panel stays reachable through the status menu.
            try? registrar.register(previous, onPress: onPress)
            logger.error(
                "shortcut change to \(combo.displayString, privacy: .public) failed: \(String(describing: error), privacy: .public)"
            )
            throw error
        }

        preferences.setPanelToggleShortcut(combo == .defaultTogglePanel ? nil : combo)
        logger.info(
            "global shortcut changed: \(previous.displayString, privacy: .public) -> \(combo.displayString, privacy: .public)"
        )
    }

    /// Restores the built-in default combo (live and persisted).
    public func resetToDefault() throws {
        try update(to: .defaultTogglePanel)
    }
}
