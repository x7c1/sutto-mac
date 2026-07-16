import Foundation

/// One recorded layout selection: the layout the user applied to a window
/// belonging to a given app (identified by a hash of its bundle identifier)
/// with a given title (identified by a hash of that title), scoped to the
/// Space Collection that was active at the time.
///
/// Mirrors `LayoutEvent` in the GNOME `domain/history/layout-event.ts`, with
/// two macOS adaptations:
///
/// - The GNOME `wmClassHash` (X11 class name) becomes ``bundleHash``, the
///   hash of the app's bundle identifier — the macOS way to identify the
///   owning application.
/// - The GNOME numeric `timestamp` becomes ``lastAppliedAt`` as a `Date`,
///   matching the persistence record described in the v0.5 design.
///
/// Both identifier fields hold *hashes* of the raw strings, never the raw
/// strings themselves: the history file must not leak which apps the user
/// runs or what their windows are titled (the GNOME privacy design). The raw
/// value → hash conversion is injected — see ``LayoutHistoryKeyHasher`` — so
/// this layer stays free of any hashing framework and depends on Foundation
/// only, as `SuttoDomain` requires.
public struct LayoutHistoryEvent: Equatable, Hashable, Sendable {
    /// The Space Collection that was active when the layout was applied.
    /// Scopes every lookup, so history recorded under one collection never
    /// leaks into another (GNOME behavior).
    public let collectionId: CollectionId

    /// Hash of the owning app's bundle identifier. Always non-empty: the
    /// recorder skips windows with no bundle identifier before an event is
    /// ever built (see ``LayoutHistory/record(bundleId:title:collectionId:layoutId:at:hashingWith:)``).
    public let bundleHash: String

    /// Hash of the window title. Non-empty even for an empty title, because
    /// the hash of the empty string is itself a non-empty digest — so an
    /// untitled window still keys consistently and can fall back to the
    /// bundle-only lookup.
    public let titleHash: String

    /// The layout that was applied.
    public let layoutId: LayoutId

    /// When the layout was applied. Drives recency: the latest event wins the
    /// exact-title lookup and the LRU ordering of ``compactEvents(_:maxPerApp:)``.
    public let lastAppliedAt: Date

    public init(
        collectionId: CollectionId,
        bundleHash: String,
        titleHash: String,
        layoutId: LayoutId,
        lastAppliedAt: Date
    ) {
        self.collectionId = collectionId
        self.bundleHash = bundleHash
        self.titleHash = titleHash
        self.layoutId = layoutId
        self.lastAppliedAt = lastAppliedAt
    }
}
