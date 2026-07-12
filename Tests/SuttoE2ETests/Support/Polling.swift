import Foundation

/// Polls `produce` until it returns a value, failing after `timeout`.
///
/// All asynchronous UI state in the e2e suite (an app becoming frontmost, a
/// panel appearing, a window frame settling) is awaited through this bounded
/// retry loop — never through a fixed sleep, which would be both slow when
/// the state arrives early and flaky when it arrives late.
@MainActor
func waitFor<T>(
    _ what: String,
    timeout: Duration = .seconds(5),
    interval: Duration = .milliseconds(50),
    produce: @MainActor () -> T?
) async throws -> T {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while true {
        if let value = produce() {
            return value
        }
        guard clock.now < deadline else {
            throw E2EFailure("timed out after \(timeout) waiting for \(what)")
        }
        try await Task.sleep(for: interval)
    }
}

/// Polls `condition` until it holds, failing after `timeout`.
@MainActor
func waitUntil(
    _ what: String,
    timeout: Duration = .seconds(5),
    interval: Duration = .milliseconds(50),
    condition: @MainActor () -> Bool
) async throws {
    _ = try await waitFor(what, timeout: timeout, interval: interval) {
        condition() ? true : nil
    }
}
