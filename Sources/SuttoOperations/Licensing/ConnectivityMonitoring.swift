/// Whether this device is on a network, implemented by the infra layer.
///
/// The port of the GNOME `NetworkStateProvider`
/// (`operations/licensing/license-operations.ts`). This is the
/// **connectivity** axis — what the OS says about the network — and is kept
/// apart from **reachability** (whether the license server answered), which
/// only a validate attempt reveals. The offline limit
/// (``SuttoDomain/LicenseGatePolicy/offlineGracePeriodDays``) is counted from
/// the last time this reported online.
///
/// Marked `@MainActor` like ``LicenseRepository`` and ``LicenseApiClient``: the
/// implementation hops its OS callbacks onto the main actor, so ``LicenseGate``
/// and the test stubs stay simple.
@MainActor
public protocol ConnectivityMonitoring: AnyObject {
    /// Whether the device is online right now.
    var isOnline: Bool { get }

    /// Starts calling `onChange` with the new value whenever the device goes
    /// online or offline. Calling it again replaces the previous callback.
    func startWatching(_ onChange: @escaping @MainActor (_ isOnline: Bool) -> Void)
}
