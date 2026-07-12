/// The position of a layout inside its container, as expression strings.
///
/// Mirrors `LayoutPosition` in `domain/layout/types.ts` of the GNOME version
/// of Sutto, keeping field names and semantics identical so JSON layout
/// definitions stay compatible between the two apps.
public struct LayoutPosition: Equatable, Sendable {
    /// Horizontal offset expression, evaluated against the container width
    /// (e.g. `"1/3"`, `"50%"`, `"100px"`, `"50% - 10px"`).
    public let x: String

    /// Vertical offset expression, evaluated against the container height
    /// (e.g. `"0"`, `"50%"`, `"10px"`).
    public let y: String

    public init(x: String, y: String) {
        self.x = x
        self.y = y
    }
}

/// The size of a layout inside its container, as expression strings.
///
/// Mirrors `LayoutSize` in `domain/layout/types.ts` of the GNOME version.
public struct LayoutSize: Equatable, Sendable {
    /// Width expression, evaluated against the container width
    /// (e.g. `"1/3"`, `"300px"`, `"100% - 20px"`).
    public let width: String

    /// Height expression, evaluated against the container height
    /// (e.g. `"100%"`, `"1/2"`, `"500px"`).
    public let height: String

    public init(width: String, height: String) {
        self.width = width
        self.height = height
    }
}

/// A window layout: a labeled region of a container described by
/// position and size expressions.
///
/// Mirrors `Layout` in `domain/layout/types.ts` of the GNOME version, minus
/// the fields that only the import/persistence machinery needs: the runtime
/// UUID (`id`) and the coordinate hash for duplicate detection (`hash`).
/// Those arrive with the JSON-import work in v0.2; adding them is purely
/// additive, so this shape stays forward-compatible.
///
/// Use ``LayoutFrameResolver`` to turn a layout into a concrete pixel frame
/// for a given container size.
public struct Layout: Equatable, Sendable {
    /// User-visible name of the layout (e.g. `"Left Half"`).
    public let label: String

    /// Position expressions relative to the container origin.
    public let position: LayoutPosition

    /// Size expressions relative to the container size.
    public let size: LayoutSize

    public init(label: String, position: LayoutPosition, size: LayoutSize) {
        self.label = label
        self.position = position
        self.size = size
    }
}

/// A named group of layouts shown together (e.g. `"vertical 2-split"` with
/// its Left Half and Right Half layouts).
///
/// Mirrors `LayoutGroup` in `domain/layout/types.ts` of the GNOME version.
public struct LayoutGroup: Equatable, Sendable {
    /// Name of the group (e.g. `"vertical 3-split"`).
    public let name: String

    /// The layouts belonging to this group, in display order.
    public let layouts: [Layout]

    public init(name: String, layouts: [Layout]) {
        self.name = name
        self.layouts = layouts
    }
}
