import Foundation
import Testing

@testable import SuttoDomain

/// The record + two-stage recommendation rule of ``LayoutHistory``: the pure
/// port of the GNOME history repository's in-memory model, minus the dropped
/// `byWindowId` stage. No clock and no hashing framework — `now` and the
/// hasher are injected.
@Suite struct LayoutHistoryTests {
    private let collection = CollectionId.generate()
    private let otherCollection = CollectionId.generate()
    private let editor = LayoutId.generate()
    private let split = LayoutId.generate()
    private let full = LayoutId.generate()
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_200)

    /// A deterministic stand-in for the real (CryptoKit, outer-layer) hasher:
    /// identity keeps the stored keys readable in assertions. The domain only
    /// requires determinism, not any particular digest.
    private let hasher: LayoutHistoryKeyHasher = { $0 }

    // MARK: - Recording and the exact-title lookup

    @Test func recordsAndRecommendsTheLayoutForTheSameWindow() {
        var history = LayoutHistory()
        history.record(
            bundleId: "com.apple.TextEdit", title: "notes.txt",
            collectionId: collection, layoutId: editor, at: t0, hashingWith: hasher)

        let recommended = history.recommendedLayout(
            bundleId: "com.apple.TextEdit", title: "notes.txt",
            collectionId: collection, hashingWith: hasher)

        #expect(recommended == editor)
    }

    @Test func recommendsNothingForAnUnknownApp() {
        let history = LayoutHistory()
        #expect(
            history.recommendedLayout(
                bundleId: "com.apple.Safari", title: "",
                collectionId: collection, hashingWith: hasher) == nil)
    }

    /// Re-applying to the same window updates the recommendation to the
    /// latest choice.
    @Test func theLatestSelectionForATitleWins() {
        var history = LayoutHistory()
        history.record(
            bundleId: "app", title: "doc", collectionId: collection,
            layoutId: editor, at: t0, hashingWith: hasher)
        history.record(
            bundleId: "app", title: "doc", collectionId: collection,
            layoutId: split, at: t1, hashingWith: hasher)

        #expect(
            history.recommendedLayout(
                bundleId: "app", title: "doc", collectionId: collection,
                hashingWith: hasher) == split)
    }

    // MARK: - Lookup priority: exact title over bundle fallback

    /// An exact title match outranks the bundle-only fallback even when the
    /// fallback points at a more recently used layout.
    @Test func exactTitleMatchOutranksTheMoreRecentBundleFallback() {
        var history = LayoutHistory()
        history.record(
            bundleId: "app", title: "doc-a", collectionId: collection,
            layoutId: editor, at: t0, hashingWith: hasher)
        // A newer selection under a different title moves the bundle LRU
        // front to `split`, but `doc-a` still has its own exact match.
        history.record(
            bundleId: "app", title: "doc-b", collectionId: collection,
            layoutId: split, at: t1, hashingWith: hasher)

        #expect(
            history.recommendedLayout(
                bundleId: "app", title: "doc-a", collectionId: collection,
                hashingWith: hasher) == editor)
    }

    /// A title never seen for the app falls back to the app's most recently
    /// used layout.
    @Test func anUnseenTitleFallsBackToTheMostRecentBundleLayout() {
        var history = LayoutHistory()
        history.record(
            bundleId: "app", title: "doc-a", collectionId: collection,
            layoutId: editor, at: t0, hashingWith: hasher)
        history.record(
            bundleId: "app", title: "doc-b", collectionId: collection,
            layoutId: split, at: t1, hashingWith: hasher)

        #expect(
            history.recommendedLayout(
                bundleId: "app", title: "brand-new-window", collectionId: collection,
                hashingWith: hasher) == split)
    }

    // MARK: - Collection scoping

    /// History recorded under one collection never leaks into another.
    @Test func historyIsScopedPerCollection() {
        var history = LayoutHistory()
        history.record(
            bundleId: "app", title: "doc", collectionId: collection,
            layoutId: editor, at: t0, hashingWith: hasher)

        #expect(
            history.recommendedLayout(
                bundleId: "app", title: "doc", collectionId: otherCollection,
                hashingWith: hasher) == nil)
    }

    // MARK: - Empty identifiers

    /// An empty bundle identifier is unkeyable, so recording is skipped and
    /// lookup returns nil (GNOME skips the same way on an empty wmClass).
    @Test func recordingWithAnEmptyBundleIdIsSkipped() {
        var history = LayoutHistory()
        history.record(
            bundleId: "", title: "doc", collectionId: collection,
            layoutId: editor, at: t0, hashingWith: hasher)

        #expect(history.events.isEmpty)
        #expect(
            history.recommendedLayout(
                bundleId: "", title: "doc", collectionId: collection,
                hashingWith: hasher) == nil)
    }

    /// An empty title is fine: it keys like any other title and still
    /// resolves through the bundle fallback for other windows.
    @Test func anEmptyTitleIsKeyedAndRecommendable() {
        var history = LayoutHistory()
        history.record(
            bundleId: "app", title: "", collectionId: collection,
            layoutId: full, at: t0, hashingWith: hasher)

        #expect(
            history.recommendedLayout(
                bundleId: "app", title: "", collectionId: collection,
                hashingWith: hasher) == full)
        #expect(
            history.recommendedLayout(
                bundleId: "app", title: "other", collectionId: collection,
                hashingWith: hasher) == full)
    }

    // MARK: - LRU cap per app

    /// The app keeps at most `maxLayoutsPerApp` distinct layoutIds; the
    /// least-recently-used is dropped. Uses one title so the retained count
    /// is governed purely by the distinct-layout cap.
    @Test func distinctLayoutsPerAppAreCappedByLRU() {
        var history = LayoutHistory()
        let layouts = (0..<(maxLayoutsPerApp + 1)).map { _ in LayoutId.generate() }
        for (offset, layout) in layouts.enumerated() {
            history.record(
                bundleId: "app", title: "doc", collectionId: collection,
                layoutId: layout, at: t0.addingTimeInterval(Double(offset)),
                hashingWith: hasher)
        }

        #expect(history.events.count == maxLayoutsPerApp)
        // The oldest layout fell out; the newest five remain.
        let retained = Set(history.events.map(\.layoutId))
        #expect(retained == Set(layouts.dropFirst()))
    }

    /// Re-using a layout refreshes its recency, so it survives eviction and
    /// stays the bundle fallback.
    @Test func reusingALayoutMovesItToTheLRUFront() {
        var history = LayoutHistory()
        history.record(
            bundleId: "app", title: "doc", collectionId: collection,
            layoutId: editor, at: t0, hashingWith: hasher)
        history.record(
            bundleId: "app", title: "doc", collectionId: collection,
            layoutId: split, at: t1, hashingWith: hasher)
        // Re-apply the older layout: it becomes most-recently-used again.
        history.record(
            bundleId: "app", title: "doc", collectionId: collection,
            layoutId: editor, at: t2, hashingWith: hasher)

        #expect(
            history.recommendedLayout(
                bundleId: "app", title: "unseen", collectionId: collection,
                hashingWith: hasher) == editor)
    }

    // MARK: - Hashing seam

    /// The store keys on the hasher's *output*, not the raw string: a hasher
    /// that maps two different raw values to the same key makes them collide.
    @Test func lookupKeysOnTheHasherOutput() {
        let caseInsensitive: LayoutHistoryKeyHasher = { $0.lowercased() }
        var history = LayoutHistory()
        history.record(
            bundleId: "Com.Example.App", title: "Doc", collectionId: collection,
            layoutId: editor, at: t0, hashingWith: caseInsensitive)

        // Different casing hashes to the same key, so it resolves.
        #expect(
            history.recommendedLayout(
                bundleId: "com.example.app", title: "doc", collectionId: collection,
                hashingWith: caseInsensitive) == editor)
    }

    /// Distinct raw values the hasher keeps distinct do not collide.
    @Test func distinctKeysDoNotCollide() {
        var history = LayoutHistory()
        history.record(
            bundleId: "app-a", title: "doc", collectionId: collection,
            layoutId: editor, at: t0, hashingWith: hasher)

        #expect(
            history.recommendedLayout(
                bundleId: "app-b", title: "doc", collectionId: collection,
                hashingWith: hasher) == nil)
    }

    // MARK: - Loading

    /// Constructing from previously stored events compacts and orders them,
    /// so an over-full or unsorted file self-heals on load.
    @Test func initCompactsStoredEvents() {
        let events = (0..<(maxLayoutsPerApp + 2)).map { offset in
            LayoutHistoryEvent(
                collectionId: collection, bundleHash: "app", titleHash: "doc",
                layoutId: LayoutId.generate(),
                lastAppliedAt: t0.addingTimeInterval(Double(offset)))
        }

        let history = LayoutHistory(events: events.shuffled())

        #expect(history.events.count == maxLayoutsPerApp)
        #expect(history.events == history.events.sorted { $0.lastAppliedAt < $1.lastAppliedAt })
    }
}
