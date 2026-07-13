import AppKit
import SuttoDomain
import SuttoOperations

/// The settings window: a Collections section (select the active
/// collection, import, delete, and preview the selected collection's
/// spaces with click-to-toggle visibility) and a Shortcuts section
/// (capture the panel-toggle combo, reset it to the default).
///
/// The window itself stays thin: list composition and active marking come
/// from ``SuttoOperations/CollectionSettingsUseCase`` (which also derives
/// the preview geometry and persists the toggles), capture validation
/// from ``SuttoDomain/ShortcutCapturePolicy``, and live shortcut
/// re-registration from ``SuttoOperations/PanelShortcutUseCase``. The GNOME
/// counterpart is the preferences window (`prefs/preferences.ts`): its
/// Spaces page puts the collection list and the space preview side by
/// side, and this window keeps that arrangement — list on the left,
/// preview on the right of a vertical separator — inside the Collections
/// section of the existing single-page layout.
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
    private var previewStack: NSStackView?
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

    private func spaceToggled(collectionId: CollectionId, spaceId: SpaceId) {
        do {
            try collections.toggleSpace(collectionId: collectionId, spaceId: spaceId)
        } catch {
            presentFailure(
                title: "Toggle Failed",
                message: "The space's visibility could not be saved. \(error.localizedDescription)"
            )
        }
        // Re-derives the preview from what was actually persisted, so the
        // dimming can never drift from the stored state.
        refresh()
    }

    // MARK: - Rendering

    /// Re-renders everything that shows state: the collection rows, the
    /// space preview, the capture field, and the Reset button. Rebuilding
    /// the rows and the preview outright keeps radio states, delete
    /// buttons, tags, and toggle dimming trivially consistent with the
    /// repository.
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

        rebuildPreview()

        captureField?.combo = shortcut.currentCombo()
        resetButton?.isEnabled = !shortcut.isDefault()

        // The content changes with imports/deletions/selection (the
        // preview resizes with the selected collection) and the window is
        // not user-resizable, so fit the frame to the content each time —
        // the GNOME preferences grow their window for larger collections
        // the same way (`expandSizeIfNeeded`).
        window.setContentSize(rootStack.fittingSize)
    }

    /// Rebuilds the space preview for the active collection: one miniature
    /// per space — disabled ones dimmed — arranged in the collection's own
    /// rows, exactly like the panel. Space numbering is continuous across
    /// rows (reading order), matching the panel's accessibility labels.
    private func rebuildPreview() {
        guard let previewStack else { return }
        previewStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let model = collections.previewModel(), !model.rows.isEmpty else {
            // Nothing to preview: an empty collection (the GNOME preview's
            // "No spaces in this collection" label) — or, in theory, no
            // resolvable collection at all, which reads the same.
            let empty = NSTextField(labelWithString: "No spaces in this collection")
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            previewStack.addArrangedSubview(empty)
            return
        }

        var spaceIndex = 0
        for row in model.rows {
            let toggles = row.spaces.map { entry -> NSView in
                let toggle = SpaceToggleButton(entry: entry, index: spaceIndex) {
                    [weak self] spaceId in
                    self?.spaceToggled(collectionId: model.collectionId, spaceId: spaceId)
                }
                spaceIndex += 1
                return toggle
            }
            let rowStack = NSStackView(views: toggles)
            rowStack.orientation = .horizontal
            rowStack.alignment = .top
            rowStack.spacing = MiniaturePanelModel.Metrics.spaceSpacing
            previewStack.addArrangedSubview(rowStack)
        }
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
        row.spacing = SettingsMetrics.controlSpacing
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
        // The GNOME group description: "Select a collection to use. Click
        // spaces in the preview to toggle visibility."
        let collectionsHint = NSTextField(
            wrappingLabelWithString:
                "The selected collection provides the layouts the panel shows. "
                + "Click a space in the preview to toggle its visibility."
        )
        collectionsHint.textColor = .secondaryLabelColor
        collectionsHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        collectionsHint.preferredMaxLayoutWidth = SettingsMetrics.hintWidth

        let rowsStack = NSStackView(views: [])
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = SettingsMetrics.rowSpacing
        collectionRowsStack = rowsStack

        let importButton = NSButton(
            title: "Import…",
            target: self,
            action: #selector(importLayouts)
        )

        // List | separator | preview, the GNOME Spaces page's split pane
        // (`createSpacesPage`: list pane, vertical separator, scrolled
        // preview) — flattened into the section, without scrolling: the
        // window sizes itself to the content instead.
        let listColumn = NSStackView(views: [rowsStack, importButton])
        listColumn.orientation = .vertical
        listColumn.alignment = .leading
        listColumn.spacing = SettingsMetrics.groupSpacing

        let preview = NSStackView(views: [])
        preview.orientation = .vertical
        preview.alignment = .leading
        preview.spacing = MiniaturePanelModel.Metrics.rowSpacing
        previewStack = preview

        let verticalSeparator = makeVerticalSeparator()
        let collectionsBody = NSStackView(views: [
            listColumn, verticalSeparator, preview,
        ])
        collectionsBody.orientation = .horizontal
        collectionsBody.alignment = .top
        collectionsBody.spacing = SettingsMetrics.columnSpacing
        // .top alignment leaves the separator's length undefined; run it
        // the full height of whichever column is taller.
        verticalSeparator.heightAnchor.constraint(
            equalTo: collectionsBody.heightAnchor
        ).isActive = true

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
        shortcutRow.spacing = SettingsMetrics.controlSpacing

        let stack = NSStackView(views: [
            collectionsHeader, collectionsHint, collectionsBody,
            makeSeparator(),
            shortcutsHeader, shortcutRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsMetrics.groupSpacing
        stack.setCustomSpacing(SettingsMetrics.columnSpacing, after: collectionsBody)
        let inset = SettingsMetrics.contentInset
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
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

    /// The vertical rule between the collection list and the space preview
    /// (the GNOME Spaces page's `Gtk.Separator`). NSBox draws a separator
    /// along its longer side, so a fixed 1-point width with a stretchable
    /// height keeps it vertical; the height rides the preview's.
    private func makeVerticalSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }
}
