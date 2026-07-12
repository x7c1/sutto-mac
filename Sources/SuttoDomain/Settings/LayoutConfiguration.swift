/// The user-facing JSON schema for sharing layout collections.
///
/// Mirrors `domain/settings/types.ts` of the GNOME version of Sutto, field
/// for field. This is the format users import (and the format of the sample
/// files in the GNOME repository's `docs/examples/`): a configuration layer
/// with no runtime ids or hashes — those are minted at import time, when a
/// ``LayoutConfiguration`` becomes a ``SpaceCollection``. Both apps must
/// accept exactly the same documents here; that conversion (the importer
/// flow) is ported separately.

/// One layout definition: a label plus position/size expressions.
///
/// Mirrors `LayoutSetting` in `domain/settings/types.ts`.
public struct LayoutSetting: Equatable, Sendable, Codable {
    /// User-visible name of the layout (e.g. `"Left Half"`).
    public let label: String

    /// X coordinate expression (e.g. `"1/3"`, `"50%"`, `"100px"`, `"50% - 10px"`).
    public let x: String

    /// Y coordinate expression (e.g. `"0"`, `"50%"`, `"10px"`).
    public let y: String

    /// Width expression (e.g. `"1/3"`, `"300px"`, `"100% - 20px"`).
    public let width: String

    /// Height expression (e.g. `"100%"`, `"1/2"`, `"500px"`).
    public let height: String

    public init(label: String, x: String, y: String, width: String, height: String) {
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A named, reusable group of layout definitions.
///
/// Mirrors `LayoutGroupSetting` in `domain/settings/types.ts`.
public struct LayoutGroupSetting: Equatable, Sendable, Codable {
    /// Name the spaces refer to the group by (e.g. `"vertical 3-split"`).
    public let name: String

    /// The layouts belonging to this group, in display order.
    public let layouts: [LayoutSetting]

    public init(name: String, layouts: [LayoutSetting]) {
        self.name = name
        self.layouts = layouts
    }
}

/// One space's layout-group assignment per monitor (import input).
///
/// Mirrors `SpaceSetting` in `domain/settings/types.ts`.
public struct SpaceSetting: Equatable, Sendable, Codable {
    /// Layout group *name* per monitor key, e.g. `"0" -> "vertical 3-split"`.
    /// Resolved against ``LayoutConfiguration/layoutGroups`` at import time.
    public let displays: [String: String]

    public init(displays: [String: String]) {
        self.displays = displays
    }
}

/// A row of spaces (import input).
///
/// Mirrors `SpacesRowSetting` in `domain/settings/types.ts`.
public struct SpacesRowSetting: Equatable, Sendable, Codable {
    /// The spaces in this row, in display order.
    public let spaces: [SpaceSetting]

    public init(spaces: [SpaceSetting]) {
        self.spaces = spaces
    }
}

/// A complete importable layout configuration.
///
/// Mirrors `LayoutConfiguration` in `domain/settings/types.ts`.
public struct LayoutConfiguration: Equatable, Sendable, Codable {
    /// Name for the resulting ``SpaceCollection`` (e.g. `"Work"`, `"Home"`).
    public let name: String

    /// Global, reusable layout groups the spaces refer to by name.
    public let layoutGroups: [LayoutGroupSetting]

    /// Rows of spaces.
    public let rows: [SpacesRowSetting]

    public init(name: String, layoutGroups: [LayoutGroupSetting], rows: [SpacesRowSetting]) {
        self.name = name
        self.layoutGroups = layoutGroups
        self.rows = rows
    }
}
