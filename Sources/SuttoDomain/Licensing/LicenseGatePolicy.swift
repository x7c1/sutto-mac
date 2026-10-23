import Foundation

/// The single gate decision: whether the app's gated features (panel display)
/// are unlocked, given the last authoritative status, the local trial, and the
/// device's connectivity.
///
/// The macOS port of the GNOME `shouldExtensionBeEnabled` and
/// `isOfflineGraceExceeded` (`operations/licensing/license-operations.ts`).
/// Two axes are kept apart:
///
/// - **Reachability** — whether the license server answered — never reaches
///   this policy. A server that does not answer (or has gone away) never
///   downgrades `status` (see ``ValidationOutcome/noResponse``), so it never
///   closes the gate.
/// - **Connectivity** — whether the device is on a network — is what the
///   offline limit reads. A device may be used offline for at most
///   ``offlineGracePeriodDays``, counted from the last time it was **online**
///   (not from the last successful validate), so a device keeps working as
///   long as it keeps coming online.
///
/// The rules:
///
/// - `valid` → open, unless the device is offline **and** at least
///   ``offlineGracePeriodDays`` have passed since it was last online.
/// - `trial` → open while the local trial has days left, online or offline;
///   the trial is fully local.
/// - `trialExpired` → closed. The local trial is spent and no license was
///   activated.
/// - `expired` / `invalid` → closed. Only an authoritative answer from the
///   backend produces these.
///
/// Every input is a plain value — the connectivity as a `Bool` and the time
/// since the device was last online as a day count the caller computes for its
/// own `now` — so the policy stays Foundation-only and clock-free.
public enum LicenseGatePolicy {
    /// How long a `valid` device may stay offline, in days, counted from the
    /// last time it was online. Mirrors the GNOME `OFFLINE_GRACE_PERIOD_DAYS`
    /// (`domain/licensing/license-state.ts`).
    public static let offlineGracePeriodDays: Double = 7

    /// Whether the gate is open.
    ///
    /// - Parameters:
    ///   - status: the last authoritative verdict.
    ///   - trial: the local trial counter.
    ///   - isOnline: whether the device is on a network right now.
    ///   - daysSinceLastOnline: fractional days since the device was last
    ///     online (see ``daysSinceLastOnline(_:now:)``).
    public static func isGateOpen(
        status: LicenseStatus,
        trial: TrialState,
        isOnline: Bool,
        daysSinceLastOnline: Double
    ) -> Bool {
        switch status {
        case .valid:
            return !isOfflineGraceExceeded(
                isOnline: isOnline, daysSinceLastOnline: daysSinceLastOnline)
        case .trial:
            return !trial.isExpired
        case .trialExpired, .expired, .invalid:
            return false
        }
    }

    /// Whether the device has been offline for too long: it is offline now and
    /// at least ``offlineGracePeriodDays`` have passed since it was last
    /// online. The port of the GNOME `isOfflineGraceExceeded`. Which statuses
    /// this closes is decided by ``isGateOpen(status:trial:isOnline:daysSinceLastOnline:)``.
    public static func isOfflineGraceExceeded(
        isOnline: Bool, daysSinceLastOnline: Double
    ) -> Bool {
        !isOnline && daysSinceLastOnline >= offlineGracePeriodDays
    }

    /// Fractional days from `lastOnlineAt` to `now`. A `lastOnlineAt` in the
    /// future (a clock moved backwards) counts as zero days, so a clock change
    /// never closes the gate. The port of the GNOME `daysSinceLastOnline`.
    public static func daysSinceLastOnline(_ lastOnlineAt: Date, now: Date) -> Double {
        max(0, now.timeIntervalSince(lastOnlineAt) / (24 * 60 * 60))
    }
}
