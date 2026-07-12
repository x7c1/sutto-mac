import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already keeps the app out of the Dock;
        // this is a safety net for running the bare SwiftPM binary during
        // development, where no Info.plist is present.
        NSApp.setActivationPolicy(.accessory)

        // The selection handler only logs for now; the window-placement PR
        // replaces it with one that snaps the frontmost window.
        let panel = LayoutPanel(
            groups: BuiltInPresets.standardLayoutGroups,
            selection: LayoutSelectionUseCase { layout in
                NSLog("Sutto: layout selected: %@", layout.label)
            }
        )
        layoutPanel = panel

        statusItemController = StatusItemController(
            permission: permission,
            onShowPanel: { [weak panel] in panel?.show() }
        )

        if permission.shouldPresentOnboarding() {
            let onboarding = PermissionOnboarding(permission: permission)
            permissionOnboarding = onboarding
            onboarding.present()
        }
    }
}
