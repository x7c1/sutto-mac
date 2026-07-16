import SuttoDomain

/// Persistence for the ``LicenseState`` aggregate, implemented by the infra
/// layer.
///
/// Mirrors the GNOME `LicenseRepository`
/// (`operations/licensing/license-repository.ts`), which the GNOME version
/// backs with GSettings; the macOS version backs it with a single JSON file
/// (design decision #7), matching the ``LayoutHistoryRepository`` /
/// ``MonitorEnvironmentRepository`` file convention.
///
/// ``load()`` never fails and never fabricates a worse verdict: a missing or
/// corrupt store degrades to ``LicenseState/freshTrial`` (design decision #8).
/// A read failure is not an authoritative NO, so — like the fail-open rule for
/// an unreachable backend — it must never close the gate. This is the storage
/// analogue of ``SuttoDomain/ValidationOutcome/noResponse``: a rare corruption
/// recovers by re-activating, it does not brick a paying user.
@MainActor
public protocol LicenseRepository {
    /// The stored aggregate, or ``LicenseState/freshTrial`` on first run or
    /// when the stored data is unreadable.
    func load() -> LicenseState

    /// Persists the aggregate, replacing whatever was stored before.
    func save(_ state: LicenseState) throws
}
