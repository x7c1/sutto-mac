import SuttoDomain

/// The persisted licensing aggregate: the authoritative gate status, the
/// activated-license record (once a license exists), and the local trial.
///
/// Licensing is stored as one document written all-or-nothing (design
/// decision #7), so the pieces the GNOME version keeps in separate GSettings
/// keys — `license-status`, the `License`, and the `TrialPeriod` — are bundled
/// here. Doing so lets ``LicenseRepository`` persist a single value and rules
/// out a half-written state where, say, the status is fresh but the trial is
/// stale.
///
/// ``status`` is the single source of truth the gate reads
/// (``SuttoDomain/LicenseGatePolicy``). ``record`` mirrors it in
/// ``SuttoDomain/LicenseRecord/status`` for convenience, but the aggregate's
/// ``status`` is canonical; ``updateStatus(_:)`` keeps the two in step and the
/// serializer writes ``status`` only, so the mirror can never drift on disk.
public struct LicenseState: Equatable, Sendable {
    /// The last authoritative verdict — the sole status axis the gate reads.
    /// Present even without a ``record`` (a trial that has run out is
    /// `.expired` with no license), which is why it lives here rather than
    /// only inside ``record``.
    public var status: LicenseStatus

    /// The activated license, or `nil` before any activation (the trial-only
    /// state). Mirrors the GNOME `loadLicense()` returning `null` when the key
    /// or activation id is empty.
    public var record: LicenseRecord?

    /// The local, backend-independent trial counter.
    public var trial: TrialState

    public init(status: LicenseStatus, record: LicenseRecord?, trial: TrialState) {
        self.status = status
        self.record = record
        self.trial = trial
    }

    /// A device that has never activated and just started its trial — also the
    /// degrade target when license storage is missing or corrupt, so a
    /// read failure never fabricates a worse verdict than the truth (design
    /// decision #8).
    public static let freshTrial = LicenseState(
        status: .trial, record: nil, trial: .initial)

    /// Whether the gate is open for this state, delegating to the pure
    /// ``SuttoDomain/LicenseGatePolicy`` (status + trial only; no network).
    public var isGateOpen: Bool {
        LicenseGatePolicy.isGateOpen(status: status, trial: trial)
    }

    /// Sets ``status`` and mirrors it into ``record`` so the two never
    /// disagree in memory. The canonical value remains this aggregate's
    /// ``status``.
    public mutating func updateStatus(_ newStatus: LicenseStatus) {
        status = newStatus
        record?.status = newStatus
    }
}
