import AppKit
import SuttoOperations
import UniformTypeIdentifiers
import os

/// Presents the import flow triggered from the settings window: an open
/// panel filtered to JSON files, the import use case, and an alert when the
/// import fails. This is the app's first user-facing error surface, so the
/// alert copy comes from ``SuttoOperations/LayoutImportError/userMessage``
/// — short and specific about why the file was rejected.
///
/// Success needs no dialog: the settings collection list refreshes and the
/// new collection appears there, ready to be selected — importing does not
/// activate it. A log line records what was imported (the use case emits
/// it).
@MainActor
public final class LayoutImportController {
    private let importCollection: ImportCollectionUseCase
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "import")

    public init(importCollection: ImportCollectionUseCase) {
        self.importCollection = importCollection
    }

    /// Runs the open-panel → import → report flow.
    public func present() {
        let panel = NSOpenPanel()
        panel.title = "Import Layouts"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        // An LSUIElement app is never active on its own; without this the
        // open panel appears behind the frontmost app's windows.
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        switch importCollection.importCollection(at: url) {
        case .success:
            // The use case already logged the imported collection.
            break
        case .failure(let error):
            logger.error(
                "import failed for \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            presentFailure(error)
        }
    }

    private func presentFailure(_ error: LayoutImportError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Import Failed"
        alert.informativeText = error.userMessage
        alert.runModal()
    }
}
