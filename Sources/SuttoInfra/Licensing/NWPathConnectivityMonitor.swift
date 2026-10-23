import Foundation
import Network
import SuttoOperations
import os

/// ``SuttoOperations/ConnectivityMonitoring`` backed by `NWPathMonitor`: the
/// device counts as online while the current path's status is `.satisfied`.
///
/// The macOS counterpart of the GNOME `NetworkStateProvider` implementation,
/// which reads `Gio.NetworkMonitor`. Like it, this reports connectivity only —
/// a satisfied path says nothing about whether the license server answers.
///
/// `NWPathMonitor` delivers its first path asynchronously after `start`, on
/// its own queue, so the initializer blocks briefly until that path arrives;
/// without that, ``isOnline`` read right at launch could report an
/// online device as offline and skip the launch validate. Later updates are
/// hopped onto the main actor, where ``isOnline`` changes and the callback
/// runs. Monitoring starts on construction and ends when the instance
/// deallocates.
@MainActor
public final class NWPathConnectivityMonitor: ConnectivityMonitoring {
    /// Cancelled in the (nonisolated) deinit; `NWPathMonitor` is `Sendable`.
    private let monitor: NWPathMonitor
    private var onChange: (@MainActor (Bool) -> Void)?
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "licensing")

    public private(set) var isOnline: Bool

    /// - Parameter initialPathTimeout: how long to wait for the first path
    ///   before falling back to `NWPathMonitor.currentPath`. The first path
    ///   normally arrives within milliseconds.
    public init(initialPathTimeout: TimeInterval = 1) {
        let monitor = NWPathMonitor()
        let firstPath = DispatchSemaphore(value: 0)
        let firstStatus = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        self.monitor = monitor
        isOnline = false

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let isFirst = firstStatus.withLock { status -> Bool in
                guard status == nil else { return false }
                status = online
                return true
            }
            if isFirst {
                firstPath.signal()
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.update(isOnline: online)
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "io.github.x7c1.SuttoMac.connectivity"))

        if firstPath.wait(timeout: .now() + initialPathTimeout) == .timedOut {
            logger.info("no network path reported yet; using the monitor's current path")
        }
        isOnline = firstStatus.withLock { $0 } ?? (monitor.currentPath.status == .satisfied)
        logger.info("connectivity at start: \(self.isOnline ? "online" : "offline", privacy: .public)")
    }

    deinit {
        monitor.cancel()
    }

    public func startWatching(_ onChange: @escaping @MainActor (_ isOnline: Bool) -> Void) {
        self.onChange = onChange
    }

    /// Applies a path update, calling back only when the online state changed.
    private func update(isOnline online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        logger.info("connectivity changed: \(online ? "online" : "offline", privacy: .public)")
        onChange?(online)
    }
}
