import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

/// The record + recommend + persist behaviour of ``LayoutHistoryUseCase``:
/// the operations wrapper around the pure ``LayoutHistory``, with the clock,
/// the concrete hasher, and persistence all injected.
@Suite @MainActor struct LayoutHistoryUseCaseTests {
    private let collection = CollectionId.generate()
    private let otherCollection = CollectionId.generate()
    private let editor = LayoutId.generate()
    private let split = LayoutId.generate()
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)

    /// Identity hasher, so stored keys stay readable in assertions — the
    /// use case only needs determinism, like the domain tests.
    private let hasher: LayoutHistoryKeyHasher = { $0 }

    private func makeUseCase(
        repository: InMemoryLayoutHistoryRepository,
        now: @escaping () -> Date
    ) -> LayoutHistoryUseCase {
        LayoutHistoryUseCase(repository: repository, hashingWith: hasher, now: now)
    }

    private func identity(bundle: String?, title: String?) -> WindowIdentity {
        WindowIdentity(bundleIdentifier: bundle, title: title)
    }

    // MARK: - Recording

    @Test func recordsAndPersistsWhenBundleIdentifierPresent() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })

        history.recordAppliedLayout(
            editor,
            to: identity(bundle: "com.apple.TextEdit", title: "notes.txt"),
            in: collection
        )

        #expect(repository.savedHistories.count == 1)
        #expect(repository.storedHistory.events.count == 1)
        #expect(
            history.recommendedLayout(
                for: identity(bundle: "com.apple.TextEdit", title: "notes.txt"),
                in: collection
            ) == editor)
    }

    @Test func skipsRecordingWhenBundleIdentifierIsNil() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })

        history.recordAppliedLayout(
            editor, to: identity(bundle: nil, title: "notes.txt"), in: collection)

        #expect(repository.savedHistories.isEmpty)
    }

    @Test func skipsRecordingWhenBundleIdentifierIsEmpty() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })

        history.recordAppliedLayout(
            editor, to: identity(bundle: "", title: "notes.txt"), in: collection)

        #expect(repository.savedHistories.isEmpty)
    }

    @Test func skipsRecordingWhenNoCapturedIdentity() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })

        history.recordAppliedLayout(editor, to: nil, in: collection)

        #expect(repository.savedHistories.isEmpty)
    }

    @Test func skipsRecordingWhenCollectionIsNil() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })

        history.recordAppliedLayout(
            editor, to: identity(bundle: "com.apple.TextEdit", title: "notes.txt"), in: nil)

        #expect(repository.savedHistories.isEmpty)
    }

    /// An empty title still records: it keys like any other and resolves
    /// through the bundle-only fallback (the domain skips only on an empty
    /// bundle identifier).
    @Test func recordsWithAnEmptyTitle() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })

        history.recordAppliedLayout(
            editor, to: identity(bundle: "com.example.App", title: ""), in: collection)

        #expect(repository.savedHistories.count == 1)
    }

    // MARK: - Recommendation

    /// Exact title match beats the bundle-only fallback, and an unseen title
    /// of the same app falls back to that app's most recently used layout —
    /// the domain's two-stage lookup, surfaced through the use case.
    @Test func recommendsExactTitleThenBundleLru() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })

        history.recordAppliedLayout(
            editor, to: identity(bundle: "app", title: "doc-a"), in: collection)
        // A later selection on a different window of the same app is the LRU
        // front for the bundle-only fallback.
        let laterHistory = makeUseCase(repository: repository, now: { self.t1 })
        laterHistory.recordAppliedLayout(
            split, to: identity(bundle: "app", title: "doc-b"), in: collection)

        // Exact title → the layout applied to that title.
        #expect(
            laterHistory.recommendedLayout(
                for: identity(bundle: "app", title: "doc-a"), in: collection) == editor)
        // Unseen title of the same app → the most recent layout (split, t1).
        #expect(
            laterHistory.recommendedLayout(
                for: identity(bundle: "app", title: "never-seen"), in: collection) == split)
    }

    @Test func scopesRecommendationByCollection() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })

        history.recordAppliedLayout(
            editor, to: identity(bundle: "app", title: "doc"), in: collection)

        #expect(
            history.recommendedLayout(
                for: identity(bundle: "app", title: "doc"), in: otherCollection) == nil)
    }

    @Test func recommendsNothingForANilIdentityOrCollection() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })
        history.recordAppliedLayout(
            editor, to: identity(bundle: "app", title: "doc"), in: collection)

        #expect(history.recommendedLayout(for: nil, in: collection) == nil)
        #expect(
            history.recommendedLayout(
                for: identity(bundle: "app", title: "doc"), in: nil) == nil)
    }

    // MARK: - Lazy load

    @Test func doesNotLoadHistoryAtConstruction() {
        let repository = InMemoryLayoutHistoryRepository()
        _ = makeUseCase(repository: repository, now: { self.t0 })

        #expect(repository.loadCount == 0)
    }

    @Test func loadsHistoryOnceOnFirstUse() {
        let repository = InMemoryLayoutHistoryRepository()
        let history = makeUseCase(repository: repository, now: { self.t0 })

        _ = history.recommendedLayout(
            for: identity(bundle: "app", title: "doc"), in: collection)
        history.recordAppliedLayout(
            editor, to: identity(bundle: "app", title: "doc"), in: collection)

        // Loaded exactly once, then held in memory for the rest of the run.
        #expect(repository.loadCount == 1)
    }

    /// A history persisted on a previous run is honoured after the lazy load
    /// — a recommendation surfaces without any record this run.
    @Test func recommendsFromPreviouslyStoredHistory() {
        var stored = LayoutHistory()
        stored.record(
            bundleId: "app", title: "doc", collectionId: collection,
            layoutId: editor, at: t0, hashingWith: hasher)
        let repository = InMemoryLayoutHistoryRepository(history: stored)
        let history = makeUseCase(repository: repository, now: { self.t1 })

        #expect(
            history.recommendedLayout(
                for: identity(bundle: "app", title: "doc"), in: collection) == editor)
    }
}
