import AppKit
import SuttoOperations

/// Owns the menu bar `NSStatusItem` and its menu.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let permission: AccessibilityPermissionUseCase
    private let edgeTiling: EdgeTilingCoexistenceUseCase
    private let permissionStatusMenuItem: NSMenuItem
    private let edgeTilingWarningItem: NSMenuItem
    private let edgeTilingWarningSeparator: NSMenuItem
    private let onTogglePanel: () -> Void
    private let onOpenSettings: () -> Void
    private let onShowEdgeTilingGuidance: () -> Void

    public init(
        permission: AccessibilityPermissionUseCase,
        edgeTiling: EdgeTilingCoexistenceUseCase,
        onTogglePanel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onShowEdgeTilingGuidance: @escaping () -> Void
    ) {
        self.permission = permission
        self.edgeTiling = edgeTiling
        self.onTogglePanel = onTogglePanel
        self.onOpenSettings = onOpenSettings
        self.onShowEdgeTilingGuidance = onShowEdgeTilingGuidance
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        permissionStatusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        edgeTilingWarningItem = NSMenuItem(
            title: "⚠︎ macOS edge tiling is on — fix…",
            action: nil,
            keyEquivalent: ""
        )
        edgeTilingWarningSeparator = .separator()
        super.init()

        configureButton()
        statusItem.menu = makeMenu()
        refreshPermissionStatus()
        refreshEdgeTilingWarning()
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        refreshPermissionStatus()
        refreshEdgeTilingWarning()
    }

    // MARK: - Public

    /// Re-evaluates the macOS edge-tiling warning so it clears (or appears)
    /// without a relaunch. The app calls this on foreground; `menuWillOpen`
    /// covers the menu being opened directly.
    public func refreshEdgeTilingWarning() {
        let shouldWarn = edgeTiling.shouldWarn()
        edgeTilingWarningItem.isHidden = !shouldWarn
        edgeTilingWarningSeparator.isHidden = !shouldWarn
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        onTogglePanel()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func showEdgeTilingGuidance() {
        onShowEdgeTilingGuidance()
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

        // macOS's own edge-tiling collides with Sutto's edge-trigger. This
        // warning item is present only while that OS setting is on (toggled
        // by `refreshEdgeTilingWarning`); clicking it opens guidance on how
        // to turn it off. Its dedicated separator is hidden alongside it so
        // the menu has no dangling divider when the warning is absent.
        edgeTilingWarningItem.target = self
        edgeTilingWarningItem.action = #selector(showEdgeTilingGuidance)
        menu.addItem(edgeTilingWarningItem)
        menu.addItem(edgeTilingWarningSeparator)

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
