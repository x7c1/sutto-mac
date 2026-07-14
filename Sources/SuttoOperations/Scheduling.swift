/// A single one-shot, cancellable delayed action, as required by the
/// operations layer and implemented by the infra layer on top of a main
/// run-loop `Timer`.
///
/// ``EdgeTriggerUseCase`` owns three of these — one for the 200 ms dwell
/// timer, one for the ~50 ms drag-move throttle, and one for the 500 ms
/// leave-edge grace — so each is testable against a fake that fires on demand
/// instead of a real clock. Each scheduler tracks at most one pending action: scheduling
/// again replaces the previous one, matching the "one hide timer" pattern the
/// UI layer already uses for auto-hide.
///
/// Isolated to the main actor because it drives main-thread UI work
/// (consistent with ``DragObserving`` / ``WindowControlling`` /
/// ``ScreenProviding``).
@MainActor
public protocol Scheduling {
    /// Schedules `action` to run after `delay`, replacing any action that was
    /// already pending on this scheduler.
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void)

    /// Cancels the pending action, if any. Safe to call when nothing is
    /// scheduled.
    func cancel()
}
