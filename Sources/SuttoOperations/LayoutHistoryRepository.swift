import SuttoDomain

/// Persistence for the learned ``SuttoDomain/LayoutHistory``, implemented by
/// the infra layer.
///
/// Mirrors the GNOME `LayoutHistoryRepository`
/// (`operations/history/layout-history-repository.ts`), which the GNOME
/// version implements as a file next to the collection files. Load never
/// fails: a missing or unreadable history degrades to an empty
/// ``SuttoDomain/LayoutHistory``, because learned recommendations are a
/// convenience that must never brick the app — unlike
/// ``MonitorEnvironmentRepository/load()``, which returns `nil` for "start
/// fresh", history has a natural empty value and returns it directly.
@MainActor
public protocol LayoutHistoryRepository {
    /// The stored history, or an empty history on first run or when the
    /// stored data is unreadable — the caller recommends nothing either way.
    func load() -> LayoutHistory

    /// Persists the history, replacing whatever was stored before.
    func save(_ history: LayoutHistory) throws
}
