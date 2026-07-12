import AppKit
import SuttoOperations

/// Owns the menu bar `NSStatusItem` and its menu.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let permission: AccessibilityPermissionUseCase
    private let permissionStatusMenuItem: NSMenuItem
    private let onTogglePanel: () -> Void
    private let onOpenSettings: () -> Void

    public init(
        permission: AccessibilityPermissionUseCase,
        onTogglePanel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.permission = permission
        self.onTogglePanel = onTogglePanel
        self.onOpenSettings = onOpenSettings
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

    // MARK: - Actions

    @objc private func togglePanel() {
        onTogglePanel()
    }

    @objc private func openSettings() {
        onOpenSettings()
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

        // Discoverable alternative to the global shortcut, sharing its
        // toggle behavior so the two triggers stay consistent.
        let togglePanelItem = NSMenuItem(
            title: "Toggle Panel",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        togglePanelItem.target = self
        menu.addItem(togglePanelItem)

        // Opens the settings window (collections and shortcuts; importing
        // moved there, so settings is the single import path — as in the
        // GNOME version, where import lives only in preferences). The ","
        // key equivalent renders the conventional ⌘, next to the title.
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
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
