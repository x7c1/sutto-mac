import Testing

@testable import SuttoDomain

/// The GNOME version has no `space-id.test.ts`, but `SpaceId` shares the
/// exact contract of `CollectionId`/`LayoutId`, so this suite mirrors their
/// ported tests to pin the same normalization and validation behavior.
@Suite struct SpaceIdTests {
    private static let validUUID = "550e8400-e29b-41d4-a716-446655440000"

    @Suite struct Constructor {
        @Test func createsAValidSpaceIdFromUUIDString() throws {
            let id = try SpaceId(SpaceIdTests.validUUID)
            #expect(id.description == SpaceIdTests.validUUID)
        }

        @Test func normalizesUUIDToLowercase() throws {
            let id = try SpaceId("550E8400-E29B-41D4-A716-446655440000")
            #expect(id.description == SpaceIdTests.validUUID)
        }

        @Test func throwsInvalidSpaceIdErrorForInvalidUUIDFormat() {
            #expect(throws: InvalidSpaceIdError.self) {
                try SpaceId("not-a-uuid")
            }
            #expect(throws: InvalidSpaceIdError.self) {
                try SpaceId("")
            }
        }
    }

    @Suite struct Equals {
        @Test func returnsTrueForEqualIds() throws {
            let id1 = try SpaceId(SpaceIdTests.validUUID)
            let id2 = try SpaceId(SpaceIdTests.validUUID)
            #expect(id1 == id2)
        }

        @Test func returnsFalseForDifferentIds() throws {
            let id1 = try SpaceId(SpaceIdTests.validUUID)
            let id2 = try SpaceId("660e8400-e29b-41d4-a716-446655440000")
            #expect(id1 != id2)
        }
    }

    @Suite struct Generate {
        @Test func producesACanonicalIdThatRoundTrips() throws {
            let id = SpaceId.generate()
            let reparsed = try SpaceId(id.description)
            #expect(reparsed == id)
        }

        @Test func producesDistinctIds() {
            #expect(SpaceId.generate() != SpaceId.generate())
        }
    }
}
