import Testing

@testable import SuttoDomain

/// 1:1 port of `domain/layout/collection-id.test.ts` from the GNOME version,
/// plus pins for the Swift-side additions (`generate()`).
@Suite struct CollectionIdTests {
    private static let validUUID = "550e8400-e29b-41d4-a716-446655440000"

    @Suite struct Constructor {
        @Test func createsAValidCollectionIdFromUUIDString() throws {
            let id = try CollectionId(CollectionIdTests.validUUID)
            #expect(id.description == CollectionIdTests.validUUID)
        }

        @Test func normalizesUUIDToLowercase() throws {
            let id = try CollectionId("550E8400-E29B-41D4-A716-446655440000")
            #expect(id.description == CollectionIdTests.validUUID)
        }

        @Test func throwsInvalidCollectionIdErrorForInvalidUUIDFormat() {
            #expect(throws: InvalidCollectionIdError.self) {
                try CollectionId("not-a-uuid")
            }
            #expect(throws: InvalidCollectionIdError.self) {
                try CollectionId("")
            }
        }
    }

    @Suite struct Equals {
        @Test func returnsTrueForEqualIds() throws {
            let id1 = try CollectionId(CollectionIdTests.validUUID)
            let id2 = try CollectionId(CollectionIdTests.validUUID)
            #expect(id1 == id2)
        }

        @Test func returnsFalseForDifferentIds() throws {
            let id1 = try CollectionId(CollectionIdTests.validUUID)
            let id2 = try CollectionId("660e8400-e29b-41d4-a716-446655440000")
            #expect(id1 != id2)
        }
    }

    /// Not in the GNOME test file: `generate()` is the Swift counterpart of
    /// minting an id with `uuidGenerator.generate()` at the call site.
    @Suite struct Generate {
        @Test func producesACanonicalIdThatRoundTrips() throws {
            let id = CollectionId.generate()
            let reparsed = try CollectionId(id.description)
            #expect(reparsed == id)
        }

        @Test func producesDistinctIds() {
            #expect(CollectionId.generate() != CollectionId.generate())
        }
    }
}
