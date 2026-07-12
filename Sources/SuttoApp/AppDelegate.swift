import AppKit
import os
import SuttoDomain
import SuttoInfra
import SuttoOperations
import SuttoUI

/// Composition root: instantiates the concrete infra adapters, wires them
/// into the operations layer, and hands the result to the UI. No business
/// logic lives here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permission = AccessibilityPermissionUseCase(
        checker: AccessibilityPermissionChecker()
    )
    private var statusItemController: StatusItemController?
    private var permissionOnboarding: PermissionOnboarding?
    private var layoutPanel: LayoutPanel?
    private var settingsWindow: SettingsWindowController?
    private var hotKeys: CarbonHotKeyRegistrar?
    private var panelShortcut: PanelShortcutUseCase?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already keeps the app out of the Dock;
        // this is a safety net for running the bare SwiftPM binary during
        // development, where no Info.plist is present.
        NSApp.setActivationPolicy(.accessory)

        let screens = SystemScreenProvider()

        // Selecting a layout snaps the frontmost app's focused window. The
        // layout panel is a non-activating NSPanel, so the app that was
        // frontmost when the panel appeared is still frontmost when the
        // button is clicked — placement targets that app's window.
        let placement = WindowPlacementUseCase(
            permission: AccessibilityPermissionChecker(),
            windows: AXWindowController(),
            screens: screens
        )
        // Collections persist under Application Support, the active
        // selection under UserDefaults — the same file/GSettings split the
        // GNOME version uses. With nothing imported, the panel falls back
        // to the preset generated for the connected monitors.
        let collections = FileSpaceCollectionRepository(
            directory: FileSpaceCollectionRepository.defaultDirectory()
        )
        let preferences = UserDefaultsPreferencesRepository()

        // Generate the presets for the current monitor configuration once
        // at launch, then again whenever the panel or the settings open —
        // the same ensure-on-open the GNOME version runs, so plugging in a
        // monitor mid-session is picked up without a restart.
        let presetGenerator = PresetGeneratorUseCase(
            repository: collections,
            screens: screens
        )
        presetGenerator.ensurePresetsForCurrentMonitors()

        let activeGroups = ActiveLayoutGroupsUseCase(
            repository: collections,
            preferences: preferences,
            screens: screens
        )

        let panel = LayoutPanel(
            groups: activeGroups,
            selection: LayoutSelectionUseCase { layout in
                // .public: unified logging redacts dynamic strings as
                // <private> in `log stream` by default, which would hide
                // the selected layout from this dev-facing log.
                Logger(subsystem: "io.github.x7c1.SuttoMac", category: "selection")
                    .info("layout selected: \(layout.label, privacy: .public)")
                placement.place(layout)
            }
        )
        layoutPanel = panel

        let togglePanel = PanelToggleUseCase(
            isPanelVisible: { [weak panel] in panel?.isVisible ?? false },
            showPanel: { [weak panel] in
                // Ensure-on-open, like the GNOME MainPanel.show().
                presetGenerator.ensurePresetsForCurrentMonitors()
                panel?.show()
            },
            hidePanel: { [weak panel] in panel?.hide() }
        )

        let settings = SettingsWindowController(
            collections: CollectionSettingsUseCase(
                repository: collections,
                preferences: preferences
            ),
            layoutImport: LayoutImportController(
                importCollection: ImportCollectionUseCase(
                    repository: collections,
                    fileReader: LocalFileReader()
                )
            ),
            shortcut: registerGlobalShortcut(with: togglePanel, preferences: preferences)
        )
        settingsWindow = settings

        // Ensure-on-open for settings too, mirroring the GNOME preferences
        // (`buildPreferencesUI` ensures before rendering the list).
        let presentSettings = {
            presetGenerator.ensurePresetsForCurrentMonitors()
            settings.present()
        }

        // ⌘, while the panel is open jumps to settings (GNOME behavior,
        // with the mac-conventional combo).
        panel.onOpenSettings = presentSettings

        statusItemController = StatusItemController(
            permission: permission,
            onTogglePanel: { togglePanel.toggle() },
            onOpenSettings: presentSettings
        )

        if permission.shouldPresentOnboarding() {
            let onboarding = PermissionOnboarding(permission: permission)
            permissionOnboarding = onboarding
            onboarding.present()
        }
    }

    /// Wires and registers the global panel-toggle shortcut: the captured
    /// combo from preferences, or `KeyCombo.defaultTogglePanel` when none
    /// was captured. The returned use case also serves the settings window,
    /// which re-registers live on capture.
    private func registerGlobalShortcut(
        with togglePanel: PanelToggleUseCase,
        preferences: any PreferencesRepository
    ) -> PanelShortcutUseCase {
        let registrar = CarbonHotKeyRegistrar()
        hotKeys = registrar
        let shortcut = PanelShortcutUseCase(
            preferences: preferences,
            registrar: registrar
        ) { togglePanel.toggle() }
        panelShortcut = shortcut
        do {
            try shortcut.registerCurrent()
        } catch {
            // Not fatal: the panel stays reachable through the status menu.
            // The usual cause is another app holding the same combo.
            Logger(subsystem: "io.github.x7c1.SuttoMac", category: "shortcut")
                .error(
                    "global shortcut registration failed: \(String(describing: error), privacy: .public)"
                )
        }
        return shortcut
    }
}
