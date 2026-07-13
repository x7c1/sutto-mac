import SuttoDomain

/// Persistence for the monitor-environment storage, implemented by the
/// infra layer.
///
/// Mirrors `MonitorEnvironmentRepository` in the GNOME
/// `operations/monitor/monitor-environment-repository.ts`, which the GNOME
/// version implements as a JSON file next to the collection files.
@MainActor
public protocol MonitorEnvironmentRepository {
    /// The stored environments, or `nil` when nothing was stored yet (the
    /// normal first run) or the stored data is unreadable — the caller
    /// starts fresh either way, like the GNOME `load()`.
    func load() -> MonitorEnvironmentStorage?

    /// Persists the storage, replacing whatever was stored before.
    func save(_ storage: MonitorEnvironmentStorage) throws
}
