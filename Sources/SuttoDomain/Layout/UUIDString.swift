import struct Foundation.UUID

/// Shared normalization for the UUID-backed identifier types
/// (``CollectionId``, ``LayoutId``, ``SpaceId``).
///
/// The GNOME version repeats the same logic in `collection-id.ts`,
/// `layout-id.ts`, and `space-id.ts`: trim, lowercase, then require the
/// canonical 8-4-4-4-12 hex form. The identifier types stay separate (mixing
/// a `LayoutId` into a `CollectionId` slot must not compile), but the
/// validation is one algorithm, kept in one place here.
enum UUIDString {
    /// Returns the trimmed, lowercased UUID string, or `nil` when the input
    /// does not match the canonical UUID format.
    static func normalize(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard isCanonicalUUID(normalized) else { return nil }
        return normalized
    }

    /// Mirrors the `UUID_REGEX` in the GNOME id modules:
    /// `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`
    /// (already lowercased at this point, so the `i` flag is irrelevant).
    private static func isCanonicalUUID(_ value: String) -> Bool {
        let groupLengths = [8, 4, 4, 4, 12]
        let groups = value.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.count == groupLengths.count else { return false }
        return zip(groups, groupLengths).allSatisfy { group, length in
            group.count == length && group.allSatisfy(\.isHexDigitLowercase)
        }
    }

    /// Generates a random UUID string in the canonical lowercase form,
    /// mirroring `uuidGenerator.generate()` in the GNOME `libs/uuid` module.
    static func random() -> String {
        UUID().uuidString.lowercased()
    }
}

extension Character {
    fileprivate var isHexDigitLowercase: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self)
    }
}
