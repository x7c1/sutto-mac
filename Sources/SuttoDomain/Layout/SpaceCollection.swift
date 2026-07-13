/// One virtual desktop's worth of layout assignments: which ``LayoutGroup``
/// each monitor shows, plus whether the space participates in cycling.
///
/// Mirrors `Space` in `domain/layout/types.ts` of the GNOME version. The
/// synthesized `Codable` conformance reproduces the JSON produced by
/// `serializeSpace` in `infra/file/raw-space-collection.ts`, key for key.
public struct Space: Equatable, Sendable, Codable {
    /// Stable identity of the space.
    public let id: SpaceId

    /// Whether the space is offered when cycling through spaces.
    public var enabled: Bool

    /// The layout group shown on each monitor, keyed by monitor key
    /// (e.g. `"0"`, `"1"`).
    public let displays: [String: LayoutGroup]

    public init(id: SpaceId, enabled: Bool, displays: [String: LayoutGroup]) {
        self.id = id
        self.enabled = enabled
        self.displays = displays
    }
}

/// A horizontal row of ``Space``s as presented in the collection editor.
///
/// Mirrors `SpacesRow` in `domain/layout/types.ts` of the GNOME version.
public struct SpacesRow: Equatable, Sendable, Codable {
    /// The spaces in this row, in display order.
    public let spaces: [Space]

    public init(spaces: [Space]) {
        self.spaces = spaces
    }
}

/// A named, user-manageable set of spaces: the top of the layout hierarchy
/// (Collection > Rows > Spaces > Displays > Layout Groups > Layouts).
///
/// Mirrors `SpaceCollection` in `domain/layout/types.ts` of the GNOME
/// version. The synthesized `Codable` conformance reproduces the
/// `RawSpaceCollection` JSON storage format of
/// `infra/file/raw-space-collection.ts` (the GNOME app persists an array of
/// these, so a whole file decodes as `[SpaceCollection]`), which keeps
/// collections exported by one app importable by the other.
public struct SpaceCollection: Equatable, Sendable, Codable {
    /// Stable identity of the collection.
    public let id: CollectionId

    /// User-visible name (e.g. `"Work"`, `"Home"`).
    public var name: String

    /// The rows of spaces, top to bottom.
    public var rows: [SpacesRow]

    public init(id: CollectionId, name: String, rows: [SpacesRow]) {
        self.id = id
        self.name = name
        self.rows = rows
    }
}

extension SpaceCollection {
    /// The space with `spaceId`, wherever it sits in the rows — the lookup
    /// the settings toggle reads the current enabled state from (the GNOME
    /// repository's `findSpace`).
    public func space(withId spaceId: SpaceId) -> Space? {
        rows.flatMap(\.spaces).first { $0.id == spaceId }
    }

    /// A copy with the space's `enabled` flag set to `enabled`, or `nil`
    /// when no space with `spaceId` exists in this collection. Everything
    /// else — row structure, space order, layout assignments — is
    /// preserved.
    ///
    /// Deliberately no last-enabled-space guard: the GNOME
    /// `updateSpaceEnabled` lets the user disable every space, and the
    /// panel then shows its "no spaces" message
    /// (``MiniaturePanelModel/make(collection:screens:environments:)``
    /// returns no rows).
    public func updatingSpace(_ spaceId: SpaceId, enabled: Bool) -> SpaceCollection? {
        guard space(withId: spaceId) != nil else { return nil }
        var updated = self
        updated.rows = rows.map { row in
            SpacesRow(
                spaces: row.spaces.map { space in
                    var space = space
                    if space.id == spaceId {
                        space.enabled = enabled
                    }
                    return space
                })
        }
        return updated
    }
}
