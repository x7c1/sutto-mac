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
