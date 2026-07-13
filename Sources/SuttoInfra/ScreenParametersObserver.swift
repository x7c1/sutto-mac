import AppKit

/// Notifies its handler whenever the display configuration changes — a
/// monitor plugged in or out, a resolution or arrangement change.
///
/// This is the macOS analogue of the GNOME
/// `GnomeShellMonitorProvider.connectToMonitorChanges`, which subscribes
/// to the shell layout manager's `monitors-changed` signal:
/// `NSApplication.didChangeScreenParametersNotification` is the AppKit
/// signal for the same events. Like the GNOME original the events are
/// forwarded without debouncing — the environment update they trigger is
/// idempotent (re-detecting an unchanged setup is a no-op switch-wise),
/// so bursts are harmless.
///
/// The handler runs on the main actor (the notification is posted on the
/// main thread). Observation starts on construction and ends when the
/// instance deallocates.
@MainActor
public final class ScreenParametersObserver {
    // nonisolated(unsafe): deinit is nonisolated in Swift 6 and the token
    // must be handed back to NotificationCenter there. Safe because the
    // token is written once in init and only read in deinit.
    private nonisolated(unsafe) let observer: NSObjectProtocol

    public init(onChange: @escaping @MainActor () -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            // The notification arrives on the main queue; hop through
            // MainActor.assumeIsolated so the compiler knows it too.
            MainActor.assumeIsolated(onChange)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(observer)
    }
}
