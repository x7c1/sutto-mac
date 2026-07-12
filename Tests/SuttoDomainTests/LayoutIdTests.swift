import Testing

@testable import SuttoDomain

/// 1:1 port of `domain/layout/layout-id.test.ts` from the GNOME version,
/// plus pins for the Swift-side additions (`generate()`).
@Suite struct LayoutIdTests {
    private static let validUUID = "550e8400-e29b-41d4-a716-446655440000"

    @Suite struct Constructor {
        @Test func createsAValidLayoutIdFromUUIDString() throws {
            let id = try LayoutId(LayoutIdTests.validUUID)
            #expect(id.description == LayoutIdTests.validUUID)
        }

        @Test func normalizesUUIDToLowercase() throws {
            let id = try LayoutId("550E8400-E29B-41D4-A716-446655440000")
            #expect(id.description == LayoutIdTests.validUUID)
        }

        @Test func throwsInvalidLayoutIdErrorForInvalidUUIDFormat() {
            #expect(throws: InvalidLayoutIdError.self) {
                try LayoutId("not-a-uuid")
            }
            #expect(throws: InvalidLayoutIdError.self) {
                try LayoutId("")
            }
        }
    }

    @Suite struct Equals {
        @Test func returnsTrueForEqualIds() throws {
            let id1 = try LayoutId(LayoutIdTests.validUUID)
            let id2 = try LayoutId(LayoutIdTests.validUUID)
            #expect(id1 == id2)
        }

        @Test func returnsFalseForDifferentIds() throws {
            let id1 = try LayoutId(LayoutIdTests.validUUID)
            let id2 = try LayoutId("660e8400-e29b-41d4-a716-446655440000")
            #expect(id1 != id2)
        }
    }

    /// Not in the GNOME test file: `generate()` is the Swift counterpart of
    /// minting an id with `uuidGenerator.generate()` at the call site.
    @Suite struct Generate {
        @Test func producesACanonicalIdThatRoundTrips() throws {
            let id = LayoutId.generate()
            let reparsed = try LayoutId(id.description)
            #expect(reparsed == id)
        }

        @Test func producesDistinctIds() {
            #expect(LayoutId.generate() != LayoutId.generate())
        }
    }
}
