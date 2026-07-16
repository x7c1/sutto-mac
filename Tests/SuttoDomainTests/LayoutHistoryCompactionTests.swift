import Foundation
import Testing

@testable import SuttoDomain

/// The three-step compaction algorithm, ported from the GNOME
/// `domain/history/compaction.ts`: (1) latest event per title, (2) at most
/// `maxPerApp` distinct layoutIds per app in LRU order with each kept
/// layout's latest event, (3) the union sorted oldest-first.
@Suite struct LayoutHistoryCompactionTests {
    private let collection = CollectionId.generate()
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        bundle: String = "app",
        title: String = "doc",
        layout: LayoutId,
        offset: Double
    ) -> LayoutHistoryEvent {
        LayoutHistoryEvent(
            collectionId: collection, bundleHash: bundle, titleHash: title,
            layoutId: layout, lastAppliedAt: base.addingTimeInterval(offset))
    }

    // MARK: - Step 1: latest event per title

    /// Repeated selections for one window collapse to the single latest one.
    @Test func keepsOnlyTheLatestEventPerTitle() {
        let layout = LayoutId.generate()
        let events = [
            event(layout: layout, offset: 0),
            event(layout: layout, offset: 1),
            event(layout: layout, offset: 2),
        ]

        let compacted = compactEvents(events, maxPerApp: maxLayoutsPerApp)

        #expect(compacted.count == 1)
        #expect(compacted.first?.lastAppliedAt == base.addingTimeInterval(2))
    }

    /// A title-latest event is retained even when its layoutId has been
    /// evicted from the app's LRU set — the two-window title still resolves.
    @Test func retainsTitleLatestEventEvenWhenItsLayoutFellOutOfTheLRU() {
        let evicted = LayoutId.generate()
        var events = [event(title: "old-window", layout: evicted, offset: 0)]
        // Two newer distinct layouts under other titles push `evicted` past a
        // cap of one distinct layout.
        events.append(event(title: "w1", layout: LayoutId.generate(), offset: 1))
        events.append(event(title: "w2", layout: LayoutId.generate(), offset: 2))

        let compacted = compactEvents(events, maxPerApp: 1)

        // "old-window" is the latest for its own title, so it survives even
        // though `evicted` is not among the single kept LRU layout.
        #expect(compacted.contains { $0.titleHash == "old-window" && $0.layoutId == evicted })
    }

    // MARK: - Step 2: distinct-layout LRU cap per app

    @Test func capsDistinctLayoutsPerAppKeepingTheMostRecent() {
        // Same title so the retained count is governed purely by the cap.
        let layouts = (0..<4).map { _ in LayoutId.generate() }
        let events = layouts.enumerated().map { offset, layout in
            event(layout: layout, offset: Double(offset))
        }

        let compacted = compactEvents(events, maxPerApp: 2)

        #expect(compacted.count == 2)
        #expect(Set(compacted.map(\.layoutId)) == Set(layouts.suffix(2)))
    }

    /// The LRU is per app key: two apps each keep their own cap's worth.
    @Test func theLRUCapIsPerAppKey() {
        let a1 = LayoutId.generate()
        let a2 = LayoutId.generate()
        let b1 = LayoutId.generate()
        let events = [
            event(bundle: "app-a", title: "a", layout: a1, offset: 0),
            event(bundle: "app-a", title: "a", layout: a2, offset: 1),
            event(bundle: "app-b", title: "b", layout: b1, offset: 2),
        ]

        let compacted = compactEvents(events, maxPerApp: 1)

        // app-a keeps its latest (a2), app-b keeps b1.
        #expect(Set(compacted.map(\.layoutId)) == Set([a2, b1]))
    }

    // MARK: - Step 3: union sorted oldest-first

    @Test func returnsEventsSortedOldestFirst() {
        let events = [
            event(title: "w1", layout: LayoutId.generate(), offset: 2),
            event(title: "w2", layout: LayoutId.generate(), offset: 0),
            event(title: "w3", layout: LayoutId.generate(), offset: 1),
        ]

        let compacted = compactEvents(events, maxPerApp: maxLayoutsPerApp)

        #expect(compacted.map(\.lastAppliedAt) == [
            base, base.addingTimeInterval(1), base.addingTimeInterval(2),
        ])
    }

    // MARK: - Determinism

    @Test func isEmptyForNoEvents() {
        #expect(compactEvents([], maxPerApp: maxLayoutsPerApp).isEmpty)
    }

    /// Compaction is idempotent: compacting an already-compact list is a
    /// no-op, so persistence stays stable across load/save cycles.
    @Test func isIdempotent() {
        let events = (0..<8).map { offset in
            event(title: "w\(offset % 3)", layout: LayoutId.generate(), offset: Double(offset))
        }

        let once = compactEvents(events, maxPerApp: 2)
        let twice = compactEvents(once, maxPerApp: 2)

        #expect(once == twice)
    }

    /// The result does not depend on input order — same events, any order,
    /// same compacted output.
    @Test func isOrderIndependent() {
        let events = (0..<8).map { offset in
            event(title: "w\(offset % 3)", layout: LayoutId.generate(), offset: Double(offset))
        }

        let inOrder = compactEvents(events, maxPerApp: 2)
        let shuffled = compactEvents(events.shuffled(), maxPerApp: 2)

        #expect(inOrder == shuffled)
    }
}
