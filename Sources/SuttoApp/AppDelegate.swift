import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already keeps the app out of the Dock;
        // this is a safety net for running the bare SwiftPM binary during
        // development, where no Info.plist is present.
        NSApp.setActivationPolicy(.accessory)

        statusItemController = StatusItemController(permission: permission)

        if permission.shouldPresentOnboarding() {
            let onboarding = PermissionOnboarding(permission: permission)
            permissionOnboarding = onboarding
            onboarding.present()
        }
    }
}
