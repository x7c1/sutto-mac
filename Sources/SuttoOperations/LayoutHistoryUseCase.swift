import Foundation
import SuttoDomain
import os

/// Records the layout the user applies to each window and answers which
/// layout to recommend next time a window of the same app (and, ideally, the
/// same title) is targeted — the operations half of the v0.5 layout-history
/// feature.
///
/// This wraps the pure ``SuttoDomain/LayoutHistory`` rule with the two things
/// the domain deliberately does not own: persistence (through
/// ``LayoutHistoryRepository``) and a clock (`now`), injected exactly the way
/// ``MonitorEnvironmentUseCase`` injects its `now`. It also injects the
/// concrete ``SuttoDomain/LayoutHistoryKeyHasher`` (the CryptoKit SHA-256 the
/// infra layer supplies), so the domain stays Foundation-only.
///
/// The history file is *lazily loaded* on first use rather than at
/// construction, mirroring the GNOME controller, which defers the history
/// I/O until the panel is first shown. In this app the first access is the
/// recommendation lookup ``ActivePanelModelUseCase`` runs when the panel
/// opens, so no history file is read until the user actually opens the panel.
/// After the first load the in-memory ``SuttoDomain/LayoutHistory`` is the
/// source of truth for the rest of the run; every record folds into it and is
/// written straight back.
@MainActor
public final class LayoutHistoryUseCase {
    private let repository: any LayoutHistoryRepository
    private let hasher: LayoutHistoryKeyHasher
    private let now: () -> Date
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "history")

    /// The loaded history, or `nil` until the first record/recommend forces a
    /// lazy load. Held after that so records accumulate in memory and every
    /// save writes the current state.
    private var history: LayoutHistory?

    /// - Parameters:
    ///   - repository: persistence for the history; ``LayoutHistoryRepository/load()``
    ///     degrades to an empty history, so a first run or a corrupt file
    ///     simply recommends nothing.
    ///   - hasher: the concrete key hasher (the infra SHA-256), injected so
    ///     the domain rule stays free of any hashing framework.
    ///   - now: injected so tests control the timestamps that order events in
    ///     the LRU, matching ``MonitorEnvironmentUseCase``.
    public init(
        repository: any LayoutHistoryRepository,
        hashingWith hasher: @escaping LayoutHistoryKeyHasher,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.hasher = hasher
        self.now = now
    }

    /// Records that the user just applied `layoutId` to the window described
    /// by `identity`, under `collectionId`, then persists the history.
    ///
    /// Skips (with a log line, unlike the domain's silent skip) when there is
    /// nothing to key on: no captured identity, no bundle identifier, or no
    /// resolved collection. Without any one of them the selection could never
    /// be looked up again, so recording it would only grow the file with dead
    /// entries. An empty *title* is fine — it keys like any other and still
    /// resolves through the bundle-only fallback.
    public func recordAppliedLayout(
        _ layoutId: LayoutId,
        to identity: WindowIdentity?,
        in collectionId: CollectionId?
    ) {
        guard let bundleId = identity?.bundleIdentifier, !bundleId.isEmpty else {
            logger.info(
                "skipping layout-history record: the target window has no bundle identifier")
            return
        }
        guard let collectionId else {
            logger.info("skipping layout-history record: no active collection to scope it to")
            return
        }

        var history = loadedHistory()
        history.record(
            bundleId: bundleId,
            title: identity?.title ?? "",
            collectionId: collectionId,
            layoutId: layoutId,
            at: now(),
            hashingWith: hasher
        )
        self.history = history

        do {
            try repository.save(history)
        } catch {
            // Not fatal: the in-memory history stays correct for this run and
            // the next successful save catches up — the same non-fatal save
            // handling ``MonitorEnvironmentUseCase`` uses.
            logger.error(
                "failed to save layout history: \(String(describing: error), privacy: .public)")
        }
    }

    /// The layout to recommend for the window described by `identity`, under
    /// `collectionId`, or `nil` when nothing was learned (or there is nothing
    /// to key on). Reads only — never writes.
    public func recommendedLayout(
        for identity: WindowIdentity?,
        in collectionId: CollectionId?
    ) -> LayoutId? {
        guard let bundleId = identity?.bundleIdentifier, !bundleId.isEmpty else { return nil }
        guard let collectionId else { return nil }

        return loadedHistory().recommendedLayout(
            bundleId: bundleId,
            title: identity?.title ?? "",
            collectionId: collectionId,
            hashingWith: hasher
        )
    }

    /// The in-memory history, loading it from the repository on first use.
    private func loadedHistory() -> LayoutHistory {
        if let history {
            return history
        }
        let loaded = repository.load()
        history = loaded
        return loaded
    }
}
