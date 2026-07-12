import AppKit
import SuttoOperations

/// Owns the menu bar `NSStatusItem` and its menu.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let permission: AccessibilityPermissionUseCase
    private let permissionStatusMenuItem: NSMenuItem

    public init(permission: AccessibilityPermissionUseCase) {
        self.permission = permission
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        permissionStatusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        super.init()

        configureButton()
        statusItem.menu = makeMenu()
        refreshPermissionStatus()
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        refreshPermissionStatus()
    }

    // MARK: - Private

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(
            systemSymbolName: "rectangle.split.2x1",
            accessibilityDescription: "Sutto"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "Sutto"
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // Auto-enablement disables this item because it has no action,
        // which is what we want for a status-only row.
        menu.addItem(permissionStatusMenuItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Sutto",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    private func refreshPermissionStatus() {
        switch permission.currentStatus() {
        case .granted:
            permissionStatusMenuItem.title = "Accessibility: Granted"
        case .denied:
            permissionStatusMenuItem.title = "Accessibility: Not Granted"
        }
    }
}
