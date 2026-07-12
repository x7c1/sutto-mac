import AppKit

// The disposable window that the e2e suite snaps. A private helper app is
// used instead of driving a system app like TextEdit because TextEdit's
// launch state is not deterministic — it can restore previous documents or
// greet with the iCloud open panel — and force-quitting it could discard a
// developer's real work. This helper opens exactly one titled window, owns
// nothing else, and dies with the test.
//
// The process runs from a bare SwiftPM binary (no bundle), so the activation
// policy is set programmatically; a windowed process needs `.regular` to be
// eligible for frontmost status, which the scenario requires because Sutto
// places the frontmost app's focused window.

@MainActor
final class TargetAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sutto E2E Target"
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Best effort only: programmatic self-activation is advisory on
        // modern macOS and routinely refused for a process the user did not
        // launch. The test runner is what actually brings this app to the
        // front, by setting AXFrontmost through the Accessibility API
        // (TargetWindowApp.waitUntilFrontmostWithFocusedWindow).
        NSApp.activate()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = TargetAppDelegate()
app.delegate = delegate
app.run()
