import Foundation
import SuttoDomain

/// The persisted licensing aggregate: the authoritative gate status, the
/// activated-license record (once a license exists), the local trial, and the
/// last time the device was online.
///
/// Licensing is stored as one document written all-or-nothing (design
/// decision #7), so the pieces the GNOME version keeps in separate GSettings
/// keys — `license-status`, the `License`, and the `TrialPeriod` — are bundled
/// here. Doing so lets ``LicenseRepository`` persist a single value and rules
/// out a half-written state where, say, the status is fresh but the trial is
/// stale.
///
/// ``status`` is the authoritative verdict the gate reads
/// (``SuttoDomain/LicenseGatePolicy``). ``record`` mirrors it in
/// ``SuttoDomain/LicenseRecord/status`` for convenience, but the aggregate's
/// ``status`` is canonical; ``updateStatus(_:)`` keeps the two in step and the
/// serializer writes ``status`` only, so the mirror can never drift on disk.
public struct LicenseState: Equatable, Sendable {
    /// The current verdict — the status axis the gate reads. One of the
    /// five ``SuttoDomain/LicenseStatus`` values: `.trial` and `.trialExpired`
    /// are local and carry no ``record``, while `.valid`, `.expired`, and
    /// `.invalid` come from the backend. It is present even without a
    /// ``record`` (a spent trial is `.trialExpired` with no license), which is
    /// why it lives here rather than only inside ``record``.
    public var status: LicenseStatus

    /// The activated license, or `nil` before any activation (the trial-only
    /// state). Mirrors the GNOME `loadLicense()` returning `null` when the key
    /// or activation id is empty.
    public var record: LicenseRecord?

    /// The local, backend-independent trial counter.
    public var trial: TrialState

    /// The last time the device was online (connectivity, not whether the
    /// license server answered). The offline limit is counted from here; see
    /// ``SuttoDomain/LicenseGatePolicy``. The port of the GNOME
    /// `last-online-at` setting.
    public var lastOnlineAt: Date

    public init(
        status: LicenseStatus, record: LicenseRecord?, trial: TrialState, lastOnlineAt: Date
    ) {
        self.status = status
        self.record = record
        self.trial = trial
        self.lastOnlineAt = lastOnlineAt
    }

    /// A device that has never activated and just started its trial — also the
    /// degrade target when license storage is missing or corrupt, so a
    /// read failure never fabricates a worse verdict than the truth (design
    /// decision #8). `now` becomes the last-online time, so missing data
    /// never starts the offline limit early.
    public static func freshTrial(now: Date) -> LicenseState {
        LicenseState(status: .trial, record: nil, trial: .initial, lastOnlineAt: now)
    }

    /// Fractional days since the device was last online, as of `now`.
    private func daysSinceLastOnline(now: Date) -> Double {
        LicenseGatePolicy.daysSinceLastOnline(lastOnlineAt, now: now)
    }

    /// Whether the gate is open for this state, delegating to the pure
    /// ``SuttoDomain/LicenseGatePolicy`` with the device's connectivity and the
    /// time since it was last online as of `now`.
    public func isGateOpen(isOnline: Bool, now: Date) -> Bool {
        LicenseGatePolicy.isGateOpen(
            status: status, trial: trial, isOnline: isOnline,
            daysSinceLastOnline: daysSinceLastOnline(now: now))
    }

    /// Whether the gate is closed because this `valid` device has been offline
    /// for too long — the one closed state that reconnecting reopens.
    public func isOfflineTooLong(isOnline: Bool, now: Date) -> Bool {
        status == .valid
            && LicenseGatePolicy.isOfflineGraceExceeded(
                isOnline: isOnline, daysSinceLastOnline: daysSinceLastOnline(now: now))
    }

    /// Sets ``status`` and mirrors it into ``record`` so the two never
    /// disagree in memory. The canonical value remains this aggregate's
    /// ``status``.
    public mutating func updateStatus(_ newStatus: LicenseStatus) {
        status = newStatus
        record?.status = newStatus
    }
}
