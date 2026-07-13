import AppKit
import SuttoDomain
import SuttoOperations

/// The Layouts tab of the settings window: select the active collection,
/// import or delete collections, and preview the selected collection's
/// spaces with click-to-toggle visibility. The macOS counterpart of the
/// GNOME preferences' Spaces page (`prefs/spaces-page.ts`), keeping its
/// split arrangement — collection list on the left, space preview on the
/// right of a vertical separator.
///
/// The pane stays thin: list composition and active marking come from
/// ``SuttoOperations/CollectionSettingsUseCase``, which also derives the
/// preview geometry and persists the toggles. Every subview that shows
/// state is built in the initializer, so ``refresh()`` works whether or
/// not the view has been loaded into the tab view yet.
@MainActor
final class LayoutsSettingsPane: NSViewController {
    /// Notifies the window controller that the pane's fitting size may
    /// have changed (imports and deletions grow or shrink the list and the
    /// preview), so the window can be resized to fit.
    var onContentSizeChanged: (() -> Void)?

    private let collections: CollectionSettingsUseCase
    private let layoutImport: LayoutImportController

    /// The entries currently rendered, in row order; button tags index
    /// into this array.
    private var entries: [CollectionSettingsEntry] = []

    private let collectionRowsStack: NSStackView
    private let previewStack: NSStackView

    init(
        collections: CollectionSettingsUseCase,
        layoutImport: LayoutImportController
    ) {
        self.collections = collections
        self.layoutImport = layoutImport

        collectionRowsStack = NSStackView(views: [])
        collectionRowsStack.orientation = .vertical
        collectionRowsStack.alignment = .leading
        collectionRowsStack.spacing = SettingsMetrics.rowSpacing

        previewStack = NSStackView(views: [])
        previewStack.orientation = .vertical
        previewStack.alignment = .leading
        previewStack.spacing = MiniaturePanelModel.Metrics.rowSpacing

        super.init(nibName: nil, bundle: nil)
        title = SettingsTab.layouts.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LayoutsSettingsPane does not support NSCoder")
    }

    override func loadView() {
        // The GNOME group description: "Select a collection to use. Click
        // spaces in the preview to toggle visibility."
        let hint = NSTextField(
            wrappingLabelWithString:
                "The selected collection provides the layouts the panel shows. "
                + "Click a space in the preview to toggle its visibility."
        )
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.preferredMaxLayoutWidth = SettingsMetrics.hintWidth

        let importButton = NSButton(
            title: "Import…",
            target: self,
            action: #selector(importLayouts)
        )

        // List | separator | preview, the GNOME Spaces page's split pane
        // (`createSpacesPage`: list pane, vertical separator, scrolled
        // preview) — without scrolling: the window sizes itself to the
        // content instead.
        let listColumn = NSStackView(views: [collectionRowsStack, importButton])
        listColumn.orientation = .vertical
        listColumn.alignment = .leading
        listColumn.spacing = SettingsMetrics.groupSpacing

        let separator = makeVerticalSeparator()
        let body = NSStackView(views: [listColumn, separator, previewStack])
        body.orientation = .horizontal
        body.alignment = .top
        body.spacing = SettingsMetrics.columnSpacing
        // .top alignment leaves the separator's length undefined; run it
        // the full height of whichever column is taller.
        separator.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true

        let stack = NSStackView(views: [hint, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsMetrics.groupSpacing
        // The window margins live on the container (required constraints,
        // all four edges), not on stack edge insets — see
        // ``SettingsPane/containerView(wrapping:)``.
        view = SettingsPane.containerView(wrapping: stack)
    }

    /// Re-renders everything that shows state: the collection rows and the
    /// space preview. Rebuilding both outright keeps radio states, delete
    /// buttons, tags, and toggle dimming trivially consistent with the
    /// repository.
    func refresh() {
        entries = collections.entries()
        collectionRowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, entry) in entries.enumerated() {
            collectionRowsStack.addArrangedSubview(makeRow(for: entry, at: index))
        }

        rebuildPreview()

        // The content changed shape (imports/deletions/selection resize
        // the list and the preview); let the window refit — the GNOME
        // preferences grow their window for larger collections the same
        // way (`expandSizeIfNeeded`).
        onContentSizeChanged?()
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

    /// Rebuilds the space preview for the active collection: one miniature
    /// per space — disabled ones dimmed — arranged in the collection's own
    /// rows, exactly like the panel. Space numbering is continuous across
    /// rows (reading order), matching the panel's accessibility labels.
    private func rebuildPreview() {
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

    /// The vertical rule between the collection list and the space preview
    /// (the GNOME Spaces page's `Gtk.Separator`). NSBox draws a separator
    /// along its longer side, so a fixed 1-point width with a stretchable
    /// height keeps it vertical; the height rides the taller column's.
    private func makeVerticalSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func presentFailure(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
