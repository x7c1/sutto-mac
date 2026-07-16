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
    private var licenseGate: LicenseGate?
    /// Opens the licensing entry point when a gated panel-show is refused.
    /// Assigned once during launch wiring; the gate callbacks call it lazily,
    /// so it is always set by the time a user could trigger a gated action.
    private var presentSettings: (() -> Void)?
    /// Opens Settings on the License tab — the entry point a locked user needs.
    /// Assigned once during launch wiring, alongside ``presentSettings``.
    private var presentLicenseSettings: (() -> Void)?

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

        // Licensing gate (v0.6): every panel-show is gated behind a cached
        // license verdict. Assembled here from the file repository (living
        // beside the other *.sutto.json documents), the URLSession-backed API
        // client, and this device's identity. The gate reads only the cached
        // verdict — never the network — so an unreachable or vanished backend
        // never locks out a valid device (the fail-open policy). The two
        // panel-show seams below (`togglePanel`, `edgeTrigger`) consult it, and
        // the launch pass at the end of this method validates / counts a trial
        // day once.
        let licenseGate = LicenseGate(
            repository: FileLicenseRepository(
                directory: FileSpaceCollectionRepository.defaultDirectory()
            ),
            apiClient: URLSessionLicenseApiClient(baseURL: Self.licenseApiBaseURL),
            device: Self.provisionalDeviceIdentity()
        )
        self.licenseGate = licenseGate

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

        // Layout history (v0.5): remembers, per Space Collection, which
        // layout the user last applied to each app + window title, so the
        // panel can recommend it next time. The file sits next to the
        // collection files; the concrete SHA-256 key hasher lives in the
        // infra layer (CryptoKit) and is injected so the domain rule stays
        // Foundation-only. Loaded lazily on the first recommendation lookup
        // (panel open), like the GNOME controller defers its history I/O.
        let layoutHistory = LayoutHistoryUseCase(
            repository: FileLayoutHistoryRepository(
                directory: FileSpaceCollectionRepository.defaultDirectory()
            ),
            hashingWith: LayoutHistoryKeyHashing.sha256
        )

        let panelModel = ActivePanelModelUseCase(
            repository: collections,
            preferences: preferences,
            screens: screens,
            environment: monitorEnvironment,
            metrics: panelMetrics,
            session: targetSession,
            history: layoutHistory
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
                // Record the applied layout against the window captured for
                // this opening, scoped to the collection the panel is showing
                // — the same active-collection resolution the panel model
                // uses — so the next opening can recommend it. The recorder
                // skips (and logs) when there is nothing to key on.
                layoutHistory.recordAppliedLayout(
                    event.layout.id,
                    to: targetSession.targetIdentity(),
                    in: collections.activeCollection(
                        activeId: preferences.activeCollectionId(),
                        screens: screens.screens()
                    )?.id
                )
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
            hidePanel: { [weak panel] in panel?.hide() },
            // Fail-open if the gate is somehow gone: never lock the user out of
            // their own panel because of a wiring fault.
            isGateOpen: { [weak licenseGate] in licenseGate?.isOpen() ?? true },
            onGateClosed: { [weak self] in self?.openLicensingEntryPoint() }
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
            license: licenseGate,
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
        // Held so the licensing gate callbacks can reach Settings — the entry
        // point a locked user needs to activate or purchase (design decision
        // #11: Settings stays reachable while the gate is closed).
        self.presentSettings = presentSettings

        // The licensing-gate entry point opens Settings straight on the License
        // tab, so a locked user lands on activation/purchase rather than the
        // remembered tab. Same ensure-on-open as the plain present.
        self.presentLicenseSettings = {
            presetGenerator.ensurePresetsForCurrentMonitors()
            settings.present(selecting: .license)
        }

        // ⌘, while the panel is open jumps to settings (GNOME behavior,
        // with the mac-conventional combo).
        panel.onOpenSettings = presentSettings

        // macOS Sequoia ships its own window-tiling gestures enabled by
        // default — "Drag windows to screen edges to tile"
        // (`EnableTilingByEdgeDrag`) and "Drag windows to menu bar to fill
        // screen" (`EnableTopTilingByEdgeDrag`) — which react at the same
        // window-drag as Sutto's edge-trigger, so both fire at once and
        // interfere. Sutto cannot change those system settings, so it only
        // detects them (reading both keys from `com.apple.WindowManager`,
        // fresh on every call) and surfaces non-blocking guidance: a
        // status-menu warning that appears only while a conflicting gesture is
        // on, opening a dismissible how-to window that names the enabled
        // toggles. The edge-trigger itself stays enabled regardless.
        let edgeTilingCoexistence = EdgeTilingCoexistenceUseCase(
            detector: WindowManagerEdgeTilingDetector()
        )
        let edgeTilingGuidance = EdgeTilingGuidance()
        self.edgeTilingGuidance = edgeTilingGuidance

        statusItemController = StatusItemController(
            permission: permission,
            edgeTiling: edgeTilingCoexistence,
            // The menu's license line shares the settings pane's wording, read
            // fresh from the gate each time the menu opens.
            licenseStatusText: { [weak licenseGate] in
                guard let licenseGate else { return "" }
                return LicensePresentation.statusText(for: licenseGate.state(), now: Date())
            },
            onTogglePanel: { togglePanel.toggle() },
            onOpenSettings: presentSettings,
            onShowEdgeTilingGuidance: {
                edgeTilingGuidance.present(conflicts: edgeTilingCoexistence.currentConflicts())
            }
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
            hideTimer: TimerScheduler(),
            // Same gate as the shortcut/menu path, checked right before the
            // edge trigger would reveal the panel. Fail-open if the gate is
            // gone, for the same reason as the toggle path.
            isGateOpen: { [weak licenseGate] in licenseGate?.isOpen() ?? true },
            onGateClosed: { [weak self] in self?.openLicensingEntryPoint() }
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

        // Launch licensing pass (design decisions #9 / #10), run once here and
        // never on a timer. Ordered validate → record so a device whose
        // validate downgraded it does not then also count a trial day:
        //  - a `valid` device attempts a single validate; a no-answer keeps the
        //    cached verdict (fail-open), and only an authoritative NO downgrades;
        //  - a `trial` device counts today as one day of use (at most once per
        //    calendar day), closing the gate when the 30 days are spent.
        // Both are no-ops for the other states, so calling them unconditionally
        // is safe. Off the launch path in a Task since validate is async; the
        // gate wiring above does not depend on it having finished.
        Task { [licenseGate] in
            await licenseGate.validateOnLaunch()
            licenseGate.recordTrialUsageOnLaunch()
        }
    }

    /// Opens the entry point a user reaches when the licensing gate refuses a
    /// panel-show — the License settings tab, where they activate a key or
    /// start a purchase. Settings deliberately stays outside the gate so it is
    /// reachable while locked (design decision #11).
    private func openLicensingEntryPoint() {
        presentLicenseSettings?()
    }

    /// The license backend root the API client posts to.
    ///
    /// TODO(sub-PR B1): replace with the real license API base URL once the
    /// backend is live. Until then it points at a non-resolving host, so every
    /// activate/validate returns `.noResponse` — which, by the fail-open
    /// policy, leaves a valid device unlocked and lets a trial count locally.
    private static let licenseApiBaseURL = URL(string: "https://license.sutto.invalid")!

    /// This device's provisional identity for activation.
    ///
    /// TODO(sub-PR B1): derive the real device id (an `IOPlatformUUID` versus a
    /// generated-and-persisted UUID) and label to match the backend's
    /// activation contract and its device-limit accounting. For now the local
    /// machine name stands in for both id and label.
    private static func provisionalDeviceIdentity() -> DeviceIdentity {
        let name = Host.current().localizedName ?? "Mac"
        return DeviceIdentity(id: name, label: name)
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
