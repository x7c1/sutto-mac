import AppKit
import SuttoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionChecker = AccessibilityPermissionChecker()
    private var statusItemController: StatusItemController?
    private var permissionOnboarding: PermissionOnboarding?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already keeps the app out of the Dock;
        // this is a safety net for running the bare SwiftPM binary during
        // development, where no Info.plist is present.
        NSApp.setActivationPolicy(.accessory)

        statusItemController = StatusItemController(permissionChecker: permissionChecker)

        if PermissionOnboardingPolicy.shouldPresent(for: permissionChecker.currentStatus()) {
            let onboarding = PermissionOnboarding(permissionChecker: permissionChecker)
            permissionOnboarding = onboarding
            onboarding.present()
        }
    }
}
