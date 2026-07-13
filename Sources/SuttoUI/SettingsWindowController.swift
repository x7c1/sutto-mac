import AppKit
import SuttoDomain
import SuttoOperations

/// The settings window: a macOS-standard preferences window with toolbar
/// tabs (`NSTabViewController` in `.toolbar` style), one tab per settings
/// area — ``SettingsTab`` lists them. The GNOME counterpart is the
/// preferences window (`prefs/preferences.ts`) with its page list; the
/// toolbar-tab arrangement is the mac convention for the same structure.
///
/// The window title follows the selected tab, the window resizes to fit
/// each tab's content (animated, the System Settings behavior), and the
/// last-selected tab is remembered across opens in `UserDefaults` — every
/// entry point (⌘, from the panel, the status menu) lands on the tab the
/// user last used.
///
/// There is a single instance wired by the composition root; `present()`
/// shows the existing window (or focuses it) rather than opening a second
/// one.
@MainActor
public final class SettingsWindowController {
    private let layoutsPane: LayoutsSettingsPane
    private let shortcutsPane: ShortcutsSettingsPane

    private var window: NSWindow?
    private var tabController: NSTabViewController?

    public init(
        collections: CollectionSettingsUseCase,
        layoutImport: LayoutImportController,
        shortcut: PanelShortcutUseCase
    ) {
        layoutsPane = LayoutsSettingsPane(
            collections: collections,
            layoutImport: layoutImport
        )
        shortcutsPane = ShortcutsSettingsPane(shortcut: shortcut)
        layoutsPane.onContentSizeChanged = { [weak self] in
            self?.sizeWindowToFitSelectedTab(animated: false)
        }
    }

    /// Shows the settings window, creating it on first use and focusing
    /// the existing one afterwards. The collection list re-reads the
    /// repository on every present, so imports done elsewhere show up.
    public func present() {
        let isFirstPresentation = window == nil
        let window = self.window ?? makeWindow()
        self.window = window

        refresh()

        // An LSUIElement app is never active on its own; without this the
        // window would appear behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        if isFirstPresentation {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// Re-renders the panes if the window is on screen — called when the
    /// monitor environment switches, so the radio selection reflects the
    /// restored collection without reopening the window. The GNOME
    /// preferences reload the same way when the extension repoints the
    /// active id.
    public func refreshIfVisible() {
        guard window?.isVisible == true else { return }
        refresh()
    }

    private func refresh() {
        layoutsPane.refresh()
        shortcutsPane.refresh()
        sizeWindowToFitSelectedTab(animated: false)
    }

    // MARK: - Tab selection

    /// Reacts to a toolbar tab switch: window title, persisted selection,
    /// and an animated refit to the new tab's content — the standard
    /// preferences-window behavior, which `NSTabViewController` does not
    /// provide on its own.
    private func tabSelected(_ tab: SettingsTab) {
        window?.title = tab.title
        tab.persist()
        sizeWindowToFitSelectedTab(animated: true)
    }

    /// Resizes the window so its content area fits the selected pane's
    /// fitting size, keeping the top-left corner in place (windows grow
    /// downward on macOS, matching how System Settings refits per pane).
    /// The toolbar lives in the title bar, outside the content rect, so
    /// the frame delta is taken from the actual content view rather than
    /// `frameRect(forContentRect:)`, which ignores toolbars.
    private func sizeWindowToFitSelectedTab(animated: Bool) {
        guard
            let window,
            let tabController,
            tabController.tabViewItems.indices.contains(tabController.selectedTabViewItemIndex),
            let pane = tabController.tabViewItems[tabController.selectedTabViewItemIndex]
                .viewController
        else { return }

        let target = pane.view.fittingSize
        guard target.width > 0, target.height > 0, let contentView = window.contentView
        else { return }

        var frame = window.frame
        frame.size.width += target.width - contentView.frame.width
        frame.origin.y -= target.height - contentView.frame.height
        frame.size.height += target.height - contentView.frame.height
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }

    // MARK: - Window construction

    private func makeWindow() -> NSWindow {
        let tabController = SettingsTabViewController()
        tabController.tabStyle = .toolbar
        tabController.onTabSelected = { [weak self] tab in
            self?.tabSelected(tab)
        }

        for tab in SettingsTab.allCases {
            let item = NSTabViewItem(viewController: makePane(for: tab))
            item.label = tab.title
            item.identifier = tab.rawValue
            item.image = NSImage(
                systemSymbolName: tab.symbolName,
                accessibilityDescription: tab.title
            )
            tabController.addTabViewItem(item)
        }

        let restored = SettingsTab.restored()
        tabController.selectedTabViewItemIndex =
            SettingsTab.allCases.firstIndex(of: restored) ?? 0
        self.tabController = tabController

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Centered icon-over-label toolbar items, the preferences look.
        window.toolbarStyle = .preference
        window.contentViewController = tabController
        // The selection above ran before the window existed, so set the
        // title it would have set.
        window.title = restored.title
        return window
    }

    /// The pane for a tab. New tabs (a future License tab, say) add their
    /// case to ``SettingsTab`` and their pane here.
    private func makePane(for tab: SettingsTab) -> NSViewController {
        switch tab {
        case .layouts: return layoutsPane
        case .shortcuts: return shortcutsPane
        }
    }
}

/// `NSTabViewController` subclass reporting toolbar tab selection to the
/// window controller (the delegate method is the only hook AppKit offers).
@MainActor
private final class SettingsTabViewController: NSTabViewController {
    var onTabSelected: ((SettingsTab) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard
            let identifier = tabViewItem?.identifier as? String,
            let tab = SettingsTab(rawValue: identifier)
        else { return }
        onTabSelected?(tab)
    }
}
