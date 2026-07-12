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
    private var hotKeys: CarbonHotKeyRegistrar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already keeps the app out of the Dock;
        // this is a safety net for running the bare SwiftPM binary during
        // development, where no Info.plist is present.
        NSApp.setActivationPolicy(.accessory)

        // Selecting a layout snaps the frontmost app's focused window. The
        // layout panel is a non-activating NSPanel, so the app that was
        // frontmost when the panel appeared is still frontmost when the
        // button is clicked — placement targets that app's window.
        let placement = WindowPlacementUseCase(
            permission: AccessibilityPermissionChecker(),
            windows: AXWindowController(),
            screens: SystemScreenProvider()
        )
        let panel = LayoutPanel(
            groups: BuiltInPresets.standardLayoutGroups,
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
            showPanel: { [weak panel] in panel?.show() },
            hidePanel: { [weak panel] in panel?.hide() }
        )

        statusItemController = StatusItemController(
            permission: permission,
            onTogglePanel: { togglePanel.toggle() }
        )

        registerGlobalShortcut(with: togglePanel)

        if permission.shouldPresentOnboarding() {
            let onboarding = PermissionOnboarding(permission: permission)
            permissionOnboarding = onboarding
            onboarding.present()
        }
    }

    /// Registers the global panel-toggle shortcut. The combo itself is the
    /// hardcoded v0.1 default defined in `KeyCombo.defaultTogglePanel`; the
    /// v0.2 settings screen makes it user-configurable.
    private func registerGlobalShortcut(with togglePanel: PanelToggleUseCase) {
        let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "shortcut")
        let registrar = CarbonHotKeyRegistrar()
        hotKeys = registrar
        do {
            try registrar.register(.defaultTogglePanel) { togglePanel.toggle() }
            let combo = KeyCombo.defaultTogglePanel.displayString
            logger.info("global shortcut registered: \(combo, privacy: .public)")
        } catch {
            // Not fatal: the panel stays reachable through the status menu.
            // The usual cause is another app holding the same combo.
            logger.error(
                "global shortcut registration failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
