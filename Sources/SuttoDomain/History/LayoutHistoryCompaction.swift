import Foundation

/// The maximum number of *distinct* ``LayoutId`` values kept per app (per
/// `collectionId` + `bundleHash`), least-recently-used ones dropped first.
///
/// Ports the GNOME `MAX_LAYOUTS_PER_WM_CLASS = 5`
/// (`infra/file/file-layout-history-repository.ts`). "Per app" replaces
/// "per wmClass" for macOS, matching ``LayoutHistoryEvent/bundleHash``.
public let maxLayoutsPerApp = 5

/// Compacts a set of layout events, dropping everything the recommendation
/// lookup can never reach so the persisted history stays small and always
/// coherent.
///
/// A faithful port of `compactEvents` in the GNOME
/// `domain/history/compaction.ts` (the canonical algorithm — the GNOME infra
/// layer duplicates it, a smell called out in the v0.5 design; this port
/// keeps a single implementation and drives ``LayoutHistory/record(bundleId:title:collectionId:layoutId:at:hashingWith:)``
/// through it too, so there is no second copy of the LRU rule here).
///
/// The algorithm, working over the events sorted oldest-first so recency
/// follows ``LayoutHistoryEvent/lastAppliedAt``:
///
/// 1. Keep the latest event for each distinct *title* key
///    (`collectionId` + `bundleHash` + `titleHash`) — the exact-title lookup
///    only ever returns the most recent selection for that window.
/// 2. For each *app* key (`collectionId` + `bundleHash`), keep at most
///    `maxPerApp` distinct `layoutId`s in LRU order, and for each kept
///    `layoutId` keep its latest event — the bundle-only fallback returns
///    the most recently used layout, and the LRU cap bounds growth.
/// 3. Return the union, sorted oldest-first. A deterministic tiebreak on the
///    hashes and id keeps the output byte-stable for equal timestamps
///    (GNOME sorts on timestamp alone; a stable file is worth the extra key
///    and there is no cross-app file to stay bit-identical with).
public func compactEvents(_ events: [LayoutHistoryEvent], maxPerApp: Int) -> [LayoutHistoryEvent] {
    let sorted = events.sorted(by: isOlder)

    // Step 2, part 1: the LRU set of distinct layoutIds to keep per app key.
    var lruByApp: [AppKey: [LayoutId]] = [:]
    for event in sorted {
        let key = AppKey(event)
        var ids = lruByApp[key, default: []]
        ids.removeAll { $0 == event.layoutId }
        ids.insert(event.layoutId, at: 0)
        if ids.count > maxPerApp {
            ids.removeLast(ids.count - maxPerApp)
        }
        lruByApp[key] = ids
    }
    let keptLayoutIds = lruByApp.mapValues(Set.init)

    // Step 1: the latest event per title key.
    var latestByTitle: [TitleKey: LayoutHistoryEvent] = [:]
    for event in sorted {
        latestByTitle[TitleKey(event)] = event
    }

    // Step 2, part 2: the latest event per (app key, layoutId).
    var latestByAppLayout: [AppLayoutKey: LayoutHistoryEvent] = [:]
    for event in sorted {
        latestByAppLayout[AppLayoutKey(event)] = event
    }

    var kept: Set<LayoutHistoryEvent> = []
    for event in latestByTitle.values {
        kept.insert(event)
    }
    for event in latestByAppLayout.values where keptLayoutIds[AppKey(event)]?.contains(event.layoutId) == true {
        kept.insert(event)
    }

    return kept.sorted(by: isOlder)
}

/// Oldest-first ordering with a deterministic tiebreak, so compaction output
/// does not depend on the unordered set it is built from.
private func isOlder(_ lhs: LayoutHistoryEvent, _ rhs: LayoutHistoryEvent) -> Bool {
    if lhs.lastAppliedAt != rhs.lastAppliedAt {
        return lhs.lastAppliedAt < rhs.lastAppliedAt
    }
    return (lhs.collectionId.description, lhs.bundleHash, lhs.titleHash, lhs.layoutId.description)
        < (rhs.collectionId.description, rhs.bundleHash, rhs.titleHash, rhs.layoutId.description)
}

/// The app-scoped key: what the bundle-only fallback and the LRU cap group by.
private struct AppKey: Hashable {
    let collectionId: CollectionId
    let bundleHash: String

    init(_ event: LayoutHistoryEvent) {
        collectionId = event.collectionId
        bundleHash = event.bundleHash
    }
}

/// The exact-window key: what the title lookup groups by.
private struct TitleKey: Hashable {
    let collectionId: CollectionId
    let bundleHash: String
    let titleHash: String

    init(_ event: LayoutHistoryEvent) {
        collectionId = event.collectionId
        bundleHash = event.bundleHash
        titleHash = event.titleHash
    }
}

/// The (app key, layoutId) key: dedupes an app's repeated uses of one layout
/// down to its latest event.
private struct AppLayoutKey: Hashable {
    let collectionId: CollectionId
    let bundleHash: String
    let layoutId: LayoutId

    init(_ event: LayoutHistoryEvent) {
        collectionId = event.collectionId
        bundleHash = event.bundleHash
        layoutId = event.layoutId
    }
}
