import Foundation
import SuttoOperations

/// A ``Scheduling`` built on a one-shot main-run-loop `Timer`.
///
/// Mirrors the auto-hide timer pattern already used in `LayoutPanel`:
/// scheduling replaces the pending timer, and the fire callback hops through
/// `MainActor.assumeIsolated` because a run-loop timer's block is delivered on
/// the main thread but is not statically isolated. One instance owns exactly
/// one timer, so ``EdgeTriggerUseCase`` uses two — one for the dwell, one for
/// the throttle.
@MainActor
public final class TimerScheduler: Scheduling {
    private var timer: Timer?

    public init() {}

    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay.seconds, repeats: false) {
            [weak self] _ in
            // Run-loop timers fire on the main thread; the block is just not
            // statically isolated.
            MainActor.assumeIsolated {
                self?.timer = nil
                action()
            }
        }
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

extension Duration {
    /// This duration as whole-and-fractional seconds, for the `TimeInterval`
    /// APIs (`Timer`) that predate `Duration`.
    fileprivate var seconds: TimeInterval {
        let (secs, atto) = components
        return TimeInterval(secs) + TimeInterval(atto) / 1e18
    }
}
