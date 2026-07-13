import AppKit
import SuttoDomain
import SuttoOperations

/// The settings window: a Collections section (select the active
/// collection, import, delete) and a Shortcuts section (capture the
/// panel-toggle combo, reset it to the default).
///
/// The window itself stays thin: list composition and active marking come
/// from ``SuttoOperations/CollectionSettingsUseCase``, capture validation
/// from ``SuttoDomain/ShortcutCapturePolicy``, and live shortcut
/// re-registration from ``SuttoOperations/PanelShortcutUseCase``. The GNOME
/// counterpart is the preferences window (`prefs/preferences.ts`), reduced
/// to the sections v0.2 has — no space previews or per-space toggles yet.
///
/// There is a single instance wired by the composition root; `present()`
/// shows the existing window (or focuses it) rather than opening a second
/// one.
@MainActor
public final class SettingsWindowController {
    private let collections: CollectionSettingsUseCase
    private let layoutImport: LayoutImportController
    private let shortcut: PanelShortcutUseCase

    private var window: NSWindow?
    private var rootStack: NSStackView?
    private var collectionRowsStack: NSStackView?
    private var captureField: ShortcutCaptureField?
    private var resetButton: NSButton?

    /// The entries currently rendered, in row order; button tags index
    /// into this array.
    private var entries: [CollectionSettingsEntry] = []

    public init(
        collections: CollectionSettingsUseCase,
        layoutImport: LayoutImportController,
        shortcut: PanelShortcutUseCase
    ) {
        self.collections = collections
        self.layoutImport = layoutImport
        self.shortcut = shortcut
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

    /// Re-renders the collection list if the window is on screen — called
    /// when the monitor environment switches, so the radio selection
    /// reflects the restored collection without reopening the window. The
    /// GNOME preferences reload the same way when the extension repoints
    /// the active id.
    public func refreshIfVisible() {
        guard window?.isVisible == true else { return }
        refresh()
    }

    // MARK: - Actions

    @objc private func collectionSelected(_ sender: NSButton) {
        guard entries.indices.contains(sender.tag) else { return }
        collections.select(entries[sender.tag])
        refresh()
    }

    @objc private func deleteCollection(_ sender: NSButton) {
        guard
            entries.indices.contains(sender.tag),
            case .custom(let id) = entries[sender.tag].kind
        else { return }
        let name = entries[sender.tag].name

        // GNOME deletes straight from a context menu; a visible Delete
        // button is easier to hit by accident, so the mac app confirms.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "The collection is removed permanently. This cannot be undone."
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try collections.deleteCollection(id)
        } catch {
            presentFailure(
                title: "Delete Failed",
                message: "The collection could not be removed. \(error.localizedDescription)"
            )
        }
        refresh()
    }

    @objc private func importLayouts() {
        layoutImport.present()
        // Whatever happened (imported, failed, cancelled), re-reading the
        // repository renders the current truth. The import deliberately
        // does not activate the new collection — selection stays explicit,
        // like the GNOME preferences.
        refresh()
    }

    @objc private func resetShortcut() {
        do {
            try shortcut.resetToDefault()
        } catch {
            presentShortcutFailure(for: .defaultTogglePanel)
        }
        refresh()
    }

    private func shortcutCaptured(_ combo: KeyCombo) {
        do {
            try shortcut.update(to: combo)
        } catch {
            presentShortcutFailure(for: combo)
        }
        refresh()
    }

    // MARK: - Rendering

    /// Re-renders everything that shows state: the collection rows, the
    /// capture field, and the Reset button. Rebuilding the rows outright
    /// keeps radio states, delete buttons, and tags trivially consistent
    /// with `entries`.
    private func refresh() {
        guard let collectionRowsStack, let window, let rootStack else { return }

        // Any action reaching here means the user is done capturing
        // (import, delete, selection, or re-presenting the window); end a
        // capture left dangling, since clicking a button does not take
        // first-responder status away from the field on its own.
        if window.firstResponder === captureField {
            window.makeFirstResponder(nil)
        }

        entries = collections.entries()
        collectionRowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, entry) in entries.enumerated() {
            collectionRowsStack.addArrangedSubview(makeRow(for: entry, at: index))
        }

        captureField?.combo = shortcut.currentCombo()
        resetButton?.isEnabled = !shortcut.isDefault()

        // The row count changes with imports/deletions and the window is
        // not user-resizable, so fit the frame to the content each time.
        window.setContentSize(rootStack.fittingSize)
    }

    private func makeRow(for entry: CollectionSettingsEntry, at index: Int) -> NSView {
        let radio = NSButton(
            radioButtonWithTitle: entry.name,
            target: self,
            action: #selector(collectionSelected(_:))
        )
        radio.tag = index
        radio.state = entry.isActive ? .on : .off

        guard case .custom = entry.kind else {
            return radio
        }

        let delete = NSButton(
            title: "Delete",
            target: self,
            action: #selector(deleteCollection(_:))
        )
        delete.tag = index
        delete.controlSize = .small
        delete.bezelStyle = .rounded

        let row = NSStackView(views: [radio, delete])
        row.orientation = .horizontal
        row.spacing = 12
        return row
    }

    // MARK: - Failure alerts

    private func presentShortcutFailure(for combo: KeyCombo) {
        presentFailure(
            title: "Shortcut Not Available",
            message:
                "\(combo.displayString) could not be registered. "
                + "Another app may already be using it; the previous shortcut stays active."
        )
    }

    private func presentFailure(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: - Window construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sutto Settings"
        window.isReleasedWhenClosed = false

        let collectionsHeader = makeSectionHeader("Collections")
        let collectionsHint = NSTextField(
            wrappingLabelWithString:
                "The selected collection provides the layouts the panel shows."
        )
        collectionsHint.textColor = .secondaryLabelColor
        collectionsHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        collectionsHint.preferredMaxLayoutWidth = 360

        let rowsStack = NSStackView(views: [])
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6
        collectionRowsStack = rowsStack

        let importButton = NSButton(
            title: "Import…",
            target: self,
            action: #selector(importLayouts)
        )

        let shortcutsHeader = makeSectionHeader("Shortcuts")

        let field = ShortcutCaptureField(combo: shortcut.currentCombo())
        field.onCapture = { [weak self] combo in
            self?.shortcutCaptured(combo)
        }
        captureField = field

        let reset = NSButton(
            title: "Reset to Default",
            target: self,
            action: #selector(resetShortcut)
        )
        resetButton = reset

        let shortcutRow = NSStackView(views: [
            NSTextField(labelWithString: "Toggle panel:"), field, reset,
        ])
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 8

        let stack = NSStackView(views: [
            collectionsHeader, collectionsHint, rowsStack, importButton,
            makeSeparator(),
            shortcutsHeader, shortcutRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(16, after: importButton)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        rootStack = stack

        window.contentView = stack
        return window
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        let header = NSTextField(labelWithString: title)
        header.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        return header
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        return separator
    }
}
