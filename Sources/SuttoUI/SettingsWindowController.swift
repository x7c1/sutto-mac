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
    private let position: PanelPositionUseCase
    private let session: PanelTargetSession

    private var window: NSWindow?
    private var tabController: NSTabViewController?

    /// The app that was frontmost when the settings window was activated,
    /// reactivated when the window closes so closing settings does not
    /// leave Sutto (an accessory app) frontmost with no other window
    /// active. Never holds Sutto itself (see ``present()``).
    private var previousApp: NSRunningApplication?

    /// Strong reference to the window's delegate: `NSWindow.delegate` is
    /// weak, so the controller must keep it alive.
    private let windowDelegate = SettingsWindowDelegate()

    public init(
        collections: CollectionSettingsUseCase,
        layoutImport: LayoutImportController,
        shortcut: PanelShortcutUseCase,
        position: PanelPositionUseCase,
        session: PanelTargetSession
    ) {
        layoutsPane = LayoutsSettingsPane(
            collections: collections,
            layoutImport: layoutImport
        )
        shortcutsPane = ShortcutsSettingsPane(shortcut: shortcut)
        self.position = position
        self.session = session
        layoutsPane.onContentSizeChanged = { [weak self] in
            self?.sizeWindowToFitSelectedTab(animated: false)
        }
    }

    /// Shows the settings window, creating it on first use and focusing
    /// the existing one afterwards. The collection list re-reads the
    /// repository on every present, so imports done elsewhere show up.
    ///
    /// On every present the window is re-anchored to the same spot the
    /// layout panel uses — its center placed on the captured window's
    /// center, clamped into that screen's work area — so settings opens
    /// where the user was already looking instead of at screen center. The
    /// window is sized to its final size first (so the center is computed
    /// against the size the selected tab will show), then positioned.
    /// Without a captured window the anchor falls back to centering on the
    /// mouse's screen, then the main screen — the same fallback chain the
    /// panel uses.
    ///
    /// The capture and the previously-frontmost app are both read *before*
    /// activating: an accessory app is never frontmost on its own, so at
    /// this instant the frontmost app is the one the user was working in.
    /// Storing it lets ``windowWillClose`` reactivate it when settings
    /// closes, instead of leaving Sutto frontmost with no window active.
    public func present() {
        let window = self.window ?? makeWindow()
        self.window = window

        // Size first: the anchor centers the window's *final* frame, and
        // the selected tab's size is only settled after refresh().
        refresh()

        // Capture the anchor window and remember the app to restore, both
        // before the activation below makes Sutto frontmost. Only store an
        // app other than Sutto itself, so closing settings never tries to
        // "restore" to us — and a second present() while settings is
        // already frontmost keeps the real previous app.
        session.capture()
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = frontmost
        }

        let size = window.frame.size
        if let frame = position.panelFrame(width: size.width, height: size.height) {
            window.setFrameOrigin(NSPoint(x: frame.x, y: frame.y))
        } else if let screen = NSScreen.withMouse() {
            let visible = screen.visibleFrame
            window.setFrameOrigin(
                NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.midY - size.height / 2
                ))
        } else {
            window.center()
        }

        // An LSUIElement app is never active on its own; without this the
        // window would appear behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Reactivates the app that was frontmost when settings opened, then
    /// forgets it. Called from the window delegate on close so an accessory
    /// app does not linger as the frontmost app once its only window is
    /// gone. Uses the modern, non-deprecated `NSRunningApplication.activate()`.
    private func restorePreviousApp() {
        previousApp?.activate()
        previousApp = nil
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
        windowDelegate.onWillClose = { [weak self] in
            self?.restorePreviousApp()
        }
        window.delegate = windowDelegate
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

/// The settings window's delegate, forwarding the close notification to the
/// controller so it can restore the previously-frontmost app. A small
/// `NSObject` because `NSWindowDelegate` requires one and
/// ``SettingsWindowController`` is a plain controller class.
@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    var onWillClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onWillClose?()
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
