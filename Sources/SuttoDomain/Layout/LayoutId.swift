/// Error thrown when a string is not a valid UUID for a ``LayoutId``.
///
/// Mirrors `InvalidLayoutIdError` in `domain/layout/layout-id.ts` of the
/// GNOME version of Sutto.
public struct InvalidLayoutIdError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// The identity of a ``Layout``: a canonical lowercase UUID.
///
/// Mirrors `LayoutId` in `domain/layout/layout-id.ts` of the GNOME version:
/// the initializer trims and lowercases the input and rejects anything that
/// is not in the 8-4-4-4-12 UUID form, so two ids that name the same layout
/// always compare equal and serialize identically. Layout ids key the layout
/// history, so this normalization is what keeps history lookups stable
/// across export and re-import.
public struct LayoutId: Hashable, Sendable {
    private let value: String

    /// Creates an id from a UUID string, normalizing case and surrounding
    /// whitespace. Throws ``InvalidLayoutIdError`` for anything else.
    public init(_ value: String) throws {
        guard let normalized = UUIDString.normalize(value) else {
            throw InvalidLayoutIdError(message: "Invalid UUID format: \(value)")
        }
        self.value = normalized
    }

    /// Generates a fresh random id, mirroring how the GNOME version mints
    /// layout ids with `uuidGenerator.generate()` on import and preset
    /// generation.
    public static func generate() -> LayoutId {
        // A freshly generated UUID is always canonical, so this cannot throw.
        try! LayoutId(UUIDString.random())
    }
}

extension LayoutId: CustomStringConvertible {
    /// The canonical lowercase UUID string, matching `toString()` in the
    /// GNOME version.
    public var description: String { value }
}

extension LayoutId: Codable {
    /// Encodes as a bare JSON string, the representation the GNOME storage
    /// format (`infra/file/raw-space-collection.ts`) uses.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
