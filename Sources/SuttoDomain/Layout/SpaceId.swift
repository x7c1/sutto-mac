/// Error thrown when a string is not a valid UUID for a ``SpaceId``.
///
/// Mirrors `InvalidSpaceIdError` in `domain/layout/space-id.ts` of the
/// GNOME version of Sutto.
public struct InvalidSpaceIdError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// The identity of a ``Space``: a canonical lowercase UUID.
///
/// Mirrors `SpaceId` in `domain/layout/space-id.ts` of the GNOME version:
/// the initializer trims and lowercases the input and rejects anything that
/// is not in the 8-4-4-4-12 UUID form, so two ids that name the same space
/// always compare equal and serialize identically.
public struct SpaceId: Hashable, Sendable {
    private let value: String

    /// Creates an id from a UUID string, normalizing case and surrounding
    /// whitespace. Throws ``InvalidSpaceIdError`` for anything else.
    public init(_ value: String) throws {
        guard let normalized = UUIDString.normalize(value) else {
            throw InvalidSpaceIdError(message: "Invalid UUID format: \(value)")
        }
        self.value = normalized
    }

    /// Generates a fresh random id, mirroring how the GNOME version mints
    /// space ids with `uuidGenerator.generate()` on import.
    public static func generate() -> SpaceId {
        // A freshly generated UUID is always canonical, so this cannot throw.
        try! SpaceId(UUIDString.random())
    }
}

extension SpaceId: CustomStringConvertible {
    /// The canonical lowercase UUID string, matching `toString()` in the
    /// GNOME version.
    public var description: String { value }
}

extension SpaceId: Codable {
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
