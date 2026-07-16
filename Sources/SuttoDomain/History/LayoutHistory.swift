import Foundation

/// Turns a raw key string (a bundle identifier or a window title) into the
/// stored, non-reversible key that ``LayoutHistory`` records and matches on.
///
/// The concrete implementation (SHA-256 of the UTF-8 bytes, truncated to the
/// first 16 hex characters — the GNOME `hashString`) lives in an outer layer,
/// because it needs `CryptoKit`, and `SuttoDomain` must depend on Foundation
/// only (see `docs/guides/architecture.md`). Injecting it as a pure function
/// keeps the whole history rule — record, two-stage lookup, LRU cap,
/// compaction — in the domain and unit-testable, while the hashing framework
/// stays out. The transform only has to be deterministic; the domain never
/// inspects the resulting string.
public typealias LayoutHistoryKeyHasher = (String) -> String

/// The learned layout history: for each app + window title seen under a Space
/// Collection, the layout the user last applied, so the panel can recommend
/// it next time.
///
/// The macOS port of the GNOME history repository's in-memory model
/// (`infra/file/file-layout-history-repository.ts`), reduced to a pure value
/// type with no clock and no I/O — the caller injects `now` and the hasher,
/// exactly like ``MonitorEnvironmentStorage`` injects its timestamp. Two
/// deliberate departures from GNOME:
///
/// - **No `byWindowId` layer.** GNOME's first lookup stage keys off a
///   volatile per-session window id; macOS has no public API for a stable
///   window id (`_AXUIElementGetWindow` is private and bars the app from the
///   App Store), so the port drops that stage and relies on the title match
///   — see the v0.5 design, decision #3.
/// - **Always compact.** Rather than append events and compact lazily past a
///   threshold (the GNOME JSONL model), ``record(bundleId:title:collectionId:layoutId:at:hashingWith:)``
///   keeps ``events`` in the compacted, oldest-first form that persistence
///   writes verbatim — the small record count (apps × `maxLayoutsPerApp`)
///   makes a full re-compaction per record trivial and removes any duplicate
///   LRU bookkeeping.
public struct LayoutHistory: Equatable, Sendable {
    /// Every retained event, compacted and sorted oldest-first. Persistence
    /// (a later sub-PR) writes this list as-is.
    public private(set) var events: [LayoutHistoryEvent]

    /// Creates a history from previously stored events, compacting them so
    /// the invariant "`events` is compact and oldest-first" holds from the
    /// start — a load of an over-full or unsorted file self-heals.
    public init(events: [LayoutHistoryEvent] = []) {
        self.events = compactEvents(events, maxPerApp: maxLayoutsPerApp)
    }

    /// Records that the user applied `layoutId` to a window of the app
    /// `bundleId` with title `title`, under `collectionId`, at `now`.
    ///
    /// Skips silently when `bundleId` is empty: with no app to key on, the
    /// selection could not be looked up again anyway (GNOME skips the same
    /// way on an empty `wmClass`). An empty `title` is fine — it hashes and
    /// keys like any other, and still resolves through the bundle-only
    /// fallback.
    ///
    /// The new event is folded into ``events`` through
    /// ``compactEvents(_:maxPerApp:)``, so the LRU cap and title-dedup are
    /// applied in one place.
    public mutating func record(
        bundleId: String,
        title: String,
        collectionId: CollectionId,
        layoutId: LayoutId,
        at now: Date,
        hashingWith hasher: LayoutHistoryKeyHasher
    ) {
        guard !bundleId.isEmpty else { return }

        let event = LayoutHistoryEvent(
            collectionId: collectionId,
            bundleHash: hasher(bundleId),
            titleHash: hasher(title),
            layoutId: layoutId,
            lastAppliedAt: now
        )
        events = compactEvents(events + [event], maxPerApp: maxLayoutsPerApp)
    }

    /// The layout to recommend for a window of the app `bundleId` with title
    /// `title`, under `collectionId`, or `nil` when nothing was learned.
    ///
    /// Two stages, ported from the GNOME `getSelectedLayoutId` (minus the
    /// dropped `byWindowId` stage):
    ///
    /// 1. **Exact title match** — the layout last applied to a window of this
    ///    app with this exact title.
    /// 2. **Bundle-only fallback** — the layout most recently applied to *any*
    ///    window of this app, when this exact title was never seen (new
    ///    window, changed title).
    ///
    /// Returns `nil` for an empty `bundleId`, mirroring ``record(bundleId:title:collectionId:layoutId:at:hashingWith:)``.
    public func recommendedLayout(
        bundleId: String,
        title: String,
        collectionId: CollectionId,
        hashingWith hasher: LayoutHistoryKeyHasher
    ) -> LayoutId? {
        guard !bundleId.isEmpty else { return nil }

        let bundleHash = hasher(bundleId)
        let titleHash = hasher(title)

        let titleMatch = latestEvent { event in
            event.collectionId == collectionId
                && event.bundleHash == bundleHash
                && event.titleHash == titleHash
        }
        if let titleMatch {
            return titleMatch.layoutId
        }

        let bundleMatch = latestEvent { event in
            event.collectionId == collectionId && event.bundleHash == bundleHash
        }
        return bundleMatch?.layoutId
    }

    /// The most recently applied event satisfying `matches`. The bundle
    /// fallback relies on this being the LRU front: the latest event's
    /// `layoutId` is, by definition, the app's most recently used layout.
    private func latestEvent(
        where matches: (LayoutHistoryEvent) -> Bool
    ) -> LayoutHistoryEvent? {
        events.filter(matches).max { $0.lastAppliedAt < $1.lastAppliedAt }
    }
}
