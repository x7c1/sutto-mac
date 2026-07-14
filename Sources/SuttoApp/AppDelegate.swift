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
    private var edgeTilingGuidance: EdgeTilingGuidance?
    private var layoutPanel: LayoutPanel?
    private var settingsWindow: SettingsWindowController?
    private var hotKeys: CarbonHotKeyRegistrar?
    private var panelShortcut: PanelShortcutUseCase?
    private var screenObserver: ScreenParametersObserver?
    private var edgeTrigger: EdgeTriggerUseCase?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already keeps the app out of the Dock;
        // this is a safety net for running the bare SwiftPM binary during
        // development, where no Info.plist is present.
        NSApp.setActivationPolicy(.accessory)

        // An accessory app never shows a menu bar, but NSApp.mainMenu is
        // still the key-equivalent routing table: without it ⌘W cannot
        // close the settings window, ⌘Q cannot quit, and ⌘C/⌘V would be
        // dead in any text field the app ever grows. This menu exists
        // purely for that routing — nothing here is ever visible.
        NSApp.mainMenu = Self.makeMainMenu()

        let screens = SystemScreenProvider()

        // Selecting a layout snaps the window captured when the panel
        // opened. The layout panel is a non-activating NSPanel, so the app
        // frontmost when the panel appears stays frontmost — its focused
        // window is what the capture (below) records, and the same window
        // feeds both the panel's positioning and every layout applied.
        let windowController = AXWindowController()
        // The one target window per panel opening: captured when the panel
        // (or the settings window) opens and shared by positioning and
        // placement, so both act on the same window and the panel can never
        // move itself.
        let targetSession = PanelTargetSession(windows: windowController)
        let placement = WindowPlacementUseCase(
            permission: AccessibilityPermissionChecker(),
            session: targetSession,
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

        // Monitor environments: every physical display setup is identified
        // and remembers the collection the user activated in it, GNOME's
        // Monitor Environment feature. Detecting at launch either restores
        // the current setup's collection or, on the very first run,
        // migrates the pre-existing single active-collection preference
        // into this environment's record.
        let monitorEnvironment = MonitorEnvironmentUseCase(
            screens: screens,
            repository: FileMonitorEnvironmentRepository(
                directory: FileSpaceCollectionRepository.defaultDirectory()
            ),
            preferences: preferences
        )
        monitorEnvironment.activateEnvironmentForCurrentScreens()

        // Generate the presets for the current monitor configuration once
        // at launch, then again whenever the panel or the settings open —
        // the same ensure-on-open the GNOME version runs, so plugging in a
        // monitor mid-session is picked up without a restart.
        let presetGenerator = PresetGeneratorUseCase(
            repository: collections,
            screens: screens
        )
        presetGenerator.ensurePresetsForCurrentMonitors()

        // The panel's structural geometry comes from the UI layer's design
        // tokens (the one file where every tunable design value lives) and
        // is injected here; the model output carries it to the drawn
        // stacks and the keyboard navigator alike.
        let panelMetrics = PanelMetrics.structural

        let panelModel = ActivePanelModelUseCase(
            repository: collections,
            preferences: preferences,
            screens: screens,
            environment: monitorEnvironment,
            metrics: panelMetrics
        )

        // Shared by the panel and the settings window so both open at the
        // same anchor — centered over the window captured for the opening,
        // clamped into that screen's work area.
        let panelPosition = PanelPositionUseCase(
            session: targetSession,
            screens: screens
        )

        let panel = LayoutPanel(
            model: panelModel,
            selection: LayoutSelectionUseCase { event in
                // .public: unified logging redacts dynamic strings as
                // <private> in `log stream` by default, which would hide
                // the selected layout from this dev-facing log.
                Logger(subsystem: "io.github.x7c1.SuttoMac", category: "selection")
                    .info(
                        """
                        layout selected: \(event.layout.label, privacy: .public) \
                        on display \(event.displayKey, privacy: .public)
                        """)
                placement.place(event.layout, onDisplayKey: event.displayKey)
            },
            position: panelPosition,
            session: targetSession
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
                preferences: preferences,
                screens: screens,
                environment: monitorEnvironment,
                metrics: panelMetrics
            ),
            layoutImport: LayoutImportController(
                importCollection: ImportCollectionUseCase(
                    repository: collections,
                    fileReader: LocalFileReader()
                )
            ),
            shortcut: registerGlobalShortcut(with: togglePanel, preferences: preferences),
            position: panelPosition,
            session: targetSession
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

        // macOS Sequoia ships its own edge-tiling (drag a window to a screen
        // edge to tile) enabled by default, which fires at the same edges as
        // Sutto's edge-trigger. Sutto cannot change that system setting, so it
        // only detects it (reading `EnableTilingByEdgeDrag` from
        // `com.apple.WindowManager`, fresh on every call) and surfaces
        // non-blocking guidance: a status-menu warning that appears only while
        // the OS setting is on, opening a dismissible how-to window. The
        // edge-trigger itself stays enabled regardless.
        let edgeTilingCoexistence = EdgeTilingCoexistenceUseCase(
            detector: WindowManagerEdgeTilingDetector()
        )
        let edgeTilingGuidance = EdgeTilingGuidance()
        self.edgeTilingGuidance = edgeTilingGuidance

        statusItemController = StatusItemController(
            permission: permission,
            edgeTiling: edgeTilingCoexistence,
            onTogglePanel: { togglePanel.toggle() },
            onOpenSettings: presentSettings,
            onShowEdgeTilingGuidance: { edgeTilingGuidance.present() }
        )

        // Re-check the OS edge-tiling setting whenever Sutto comes to the
        // foreground, so the warning clears (or reappears) after the user
        // toggles it in System Settings — no relaunch needed. The read is a
        // single cheap prefs lookup. The menu's own `menuWillOpen` covers the
        // case of opening the menu directly.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.statusItemController?.refreshEdgeTilingWarning()
            }
        }

        // Monitor hot-plug (and arrangement/resolution changes): re-detect
        // the environment — restoring that setup's collection — make sure
        // the presets for the new monitor count exist, and refresh whatever
        // is on screen. The GNOME controller does the same on the shell's
        // monitors-changed signal (re-detect + re-show the panel).
        screenObserver = ScreenParametersObserver { [weak panel, weak settings] in
            monitorEnvironment.activateEnvironmentForCurrentScreens()
            presetGenerator.ensurePresetsForCurrentMonitors()
            if let panel, panel.isVisible {
                panel.show()
            }
            settings?.refreshIfVisible()
        }

        // Edge-drag trigger (v0.4): dragging a window to a screen edge and
        // dwelling there opens the layout panel at the cursor, which then
        // follows the drag. It ships enabled by default — there is no
        // preference toggle yet (that, and macOS-tiling coexistence, land in a
        // later sub-PR). The drag stream is a mouse-only global NSEvent
        // monitor (no extra permission); window-move discrimination reads
        // window frames over AX, which the app already holds. Starting before
        // AX permission is granted is safe: frame reads return nil, so drags
        // are simply ignored until permission lands. The three schedulers are
        // separate instances — one for the dwell delay, one for the move
        // throttle, one for the leave-edge grace — because each TimerScheduler
        // owns exactly one timer.
        let edgeTrigger = EdgeTriggerUseCase(
            drags: NSEventGlobalDragMonitor(),
            windows: windowController,
            screens: screens,
            panel: panel,
            dwellTimer: TimerScheduler(),
            throttle: TimerScheduler(),
            hideTimer: TimerScheduler()
        )
        self.edgeTrigger = edgeTrigger
        // Every panel close funnels through LayoutPanel.hide(); route that to
        // the policy so it returns to idle whether the panel closed via Escape,
        // auto-hide, a click outside, or the settings gear. Redundant calls
        // (e.g. the shortcut path's own hide) are no-ops from idle.
        panel.onDismiss = { [weak edgeTrigger] in
            edgeTrigger?.notifyPanelDismissed()
        }
        edgeTrigger.start()

        if permission.shouldPresentOnboarding() {
            let onboarding = PermissionOnboarding(permission: permission)
            permissionOnboarding = onboarding
            onboarding.present()
        }
    }

    /// The invisible main menu that gives the accessory app standard
    /// key-equivalent routing (see the call site).
    ///
    /// - Close (⌘W) is nil-targeted `performClose:`, so it travels the
    ///   key window's responder chain: the settings window (`.closable`)
    ///   closes exactly like its red close button, keeping the
    ///   single-instance show-or-focus behavior; the layout panel is a
    ///   borderless non-closable panel, so `performClose:` refuses it —
    ///   ⌘W never dismisses the panel (Escape remains its close key).
    /// - Quit (⌘Q) works from any key window while the app is active —
    ///   the standard accessory-app behavior.
    /// - The Edit block wires the standard text-editing selectors so
    ///   ⌘X/⌘C/⌘V/⌘A work in any current or future text field — the
    ///   classic LSUIElement gotcha (no menu, no editing equivalents).
    ///
    /// While the shortcut-capture field is capturing, these equivalents
    /// are *capturable* as combos rather than triggering the menu: the
    /// key window's view hierarchy gets `performKeyEquivalent` before
    /// AppKit falls through to the main menu, and the field consumes the
    /// press there.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Sutto",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        main.addItem(submenu: appMenu)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        main.addItem(submenu: fileMenu)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(
            withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        main.addItem(submenu: editMenu)

        return main
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

extension NSMenu {
    /// Adds a top-level item carrying `submenu` — the menu-bar shape
    /// AppKit expects (every top-level item wraps a submenu), without the
    /// item-title boilerplate that would never be seen anyway.
    fileprivate func addItem(submenu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        addItem(item)
    }
}
