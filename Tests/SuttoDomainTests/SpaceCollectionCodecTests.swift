import Foundation
import Testing

@testable import SuttoDomain

/// A storage-format document matching what `serializeSpaceCollection` in the
/// GNOME version writes. There is no real storage-format sample in the GNOME
/// repository (the files are written at runtime), so the shape is pinned
/// against the `RawLayout`/`RawSpace`/`RawSpaceCollection` interfaces and
/// serializers in `infra/file/raw-space-collection.ts`.
private let storageJSON = """
    [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "Work",
        "rows": [
          {
            "spaces": [
              {
                "id": "660e8400-e29b-41d4-a716-446655440000",
                "enabled": true,
                "displays": {
                  "0": {
                    "name": "vertical 2-split",
                    "layouts": [
                      {
                        "id": "770e8400-e29b-41d4-a716-446655440000",
                        "hash": "hash-e1d7a9be",
                        "label": "Left Half",
                        "position": { "x": "0", "y": "0" },
                        "size": { "width": "50%", "height": "100%" }
                      },
                      {
                        "id": "880e8400-e29b-41d4-a716-446655440000",
                        "hash": "hash-08b184c4",
                        "label": "Right Half",
                        "position": { "x": "50%", "y": "0" },
                        "size": { "width": "50%", "height": "100%" }
                      }
                    ]
                  },
                  "1": {
                    "name": "full screen",
                    "layouts": [
                      {
                        "id": "990e8400-e29b-41d4-a716-446655440000",
                        "hash": "hash-bd9c1864",
                        "label": "full",
                        "position": { "x": "0", "y": "0" },
                        "size": { "width": "100%", "height": "100%" }
                      }
                    ]
                  }
                }
              },
              {
                "id": "aa0e8400-e29b-41d4-a716-446655440000",
                "enabled": false,
                "displays": {}
              }
            ]
          },
          { "spaces": [] }
        ]
      }
    ]
    """

private func decodeStorage(_ json: String) throws -> [SpaceCollection] {
    try JSONDecoder().decode([SpaceCollection].self, from: Data(json.utf8))
}

/// JSON codec tests for the storage format of ``SpaceCollection``: the GNOME
/// version persists collections as an array of `RawSpaceCollection` objects,
/// and the synthesized `Codable` conformances must reproduce that format key
/// for key so collections move between the two apps unchanged.
@Suite struct SpaceCollectionCodecTests {
    @Suite struct Decoding {
        @Test func decodesTheFullHierarchy() throws {
            let collections = try decodeStorage(storageJSON)
            let collection = try #require(collections.first)

            #expect(collections.count == 1)
            #expect(collection.id == (try CollectionId("550e8400-e29b-41d4-a716-446655440000")))
            #expect(collection.name == "Work")
            #expect(collection.rows.count == 2)

            let firstRow = collection.rows[0]
            #expect(firstRow.spaces.count == 2)

            let space = firstRow.spaces[0]
            #expect(space.id == (try SpaceId("660e8400-e29b-41d4-a716-446655440000")))
            #expect(space.enabled)
            #expect(Set(space.displays.keys) == ["0", "1"])

            let group = try #require(space.displays["0"])
            #expect(group.name == "vertical 2-split")
            #expect(group.layouts.map(\.label) == ["Left Half", "Right Half"])

            let layout = group.layouts[0]
            #expect(layout.id == (try LayoutId("770e8400-e29b-41d4-a716-446655440000")))
            #expect(layout.hash == "hash-e1d7a9be")
            #expect(layout.position == LayoutPosition(x: "0", y: "0"))
            #expect(layout.size == LayoutSize(width: "50%", height: "100%"))

            let disabledSpace = firstRow.spaces[1]
            #expect(!disabledSpace.enabled)
            #expect(disabledSpace.displays.isEmpty)

            #expect(collection.rows[1].spaces.isEmpty)
        }

        @Test func normalizesUppercaseIdsLikeTheGnomeDeserializer() throws {
            // `deserializeSpaceCollection` funnels raw strings through the
            // id constructors, which lowercase them; decoding must match.
            let json = storageJSON.replacingOccurrences(
                of: "550e8400-e29b-41d4-a716-446655440000",
                with: "550E8400-E29B-41D4-A716-446655440000")
            let collection = try #require(try decodeStorage(json).first)
            #expect(collection.id.description == "550e8400-e29b-41d4-a716-446655440000")
        }

        @Test func ignoresUnknownFields() throws {
            // The GNOME loader runs JSON.parse plus a shallow validator, so
            // extra fields are silently carried past; the Swift decoder must
            // be at least as tolerant and simply ignore them.
            let json = storageJSON.replacingOccurrences(
                of: "\"name\": \"Work\",",
                with: "\"name\": \"Work\", \"futureField\": {\"nested\": [1, 2]},")
            let collection = try #require(try decodeStorage(json).first)
            #expect(collection.name == "Work")
        }
    }

    @Suite struct DecodingFailures {
        @Test func rejectsInvalidCollectionId() {
            let json = storageJSON.replacingOccurrences(
                of: "550e8400-e29b-41d4-a716-446655440000",
                with: "not-a-uuid")
            // Mirrors the GNOME deserializer, where `new CollectionId(raw.id)`
            // throws InvalidCollectionIdError for a malformed id.
            #expect(throws: InvalidCollectionIdError.self) {
                try decodeStorage(json)
            }
        }

        @Test func rejectsInvalidLayoutId() {
            let json = storageJSON.replacingOccurrences(
                of: "770e8400-e29b-41d4-a716-446655440000",
                with: "not-a-uuid")
            #expect(throws: InvalidLayoutIdError.self) {
                try decodeStorage(json)
            }
        }

        @Test func rejectsInvalidSpaceId() {
            let json = storageJSON.replacingOccurrences(
                of: "660e8400-e29b-41d4-a716-446655440000",
                with: "not-a-uuid")
            #expect(throws: InvalidSpaceIdError.self) {
                try decodeStorage(json)
            }
        }

        @Test func rejectsAMissingRequiredField() {
            // The GNOME shallow validator lets a layout without a hash
            // through and the import blows up later inside try/catch; either
            // way the document is rejected. Swift rejects it at decode time.
            let json = storageJSON.replacingOccurrences(
                of: "\"hash\": \"hash-e1d7a9be\",",
                with: "")
            #expect(throws: DecodingError.self) {
                try decodeStorage(json)
            }
        }

        @Test func rejectsANonArrayDocument() {
            // `isValidRawSpaceCollectionArray` requires the top level to be
            // an array.
            #expect(throws: DecodingError.self) {
                try decodeStorage("{\"id\": \"x\"}")
            }
        }
    }

    @Suite struct RoundTrip {
        @Test func decodedDocumentSurvivesEncodeAndDecode() throws {
            let decoded = try decodeStorage(storageJSON)
            let encoded = try JSONEncoder().encode(decoded)
            let redecoded = try JSONDecoder().decode([SpaceCollection].self, from: encoded)
            #expect(redecoded == decoded)
        }

        @Test func reencodedDocumentIsStructurallyEqualToTheOriginal() throws {
            let decoded = try decodeStorage(storageJSON)
            let encoded = try JSONEncoder().encode(decoded)

            let original = try #require(
                try JSONSerialization.jsonObject(with: Data(storageJSON.utf8)) as? NSArray)
            let reencoded = try #require(
                try JSONSerialization.jsonObject(with: encoded) as? NSArray)
            #expect(original == reencoded)
        }

        @Test func constructedModelSurvivesEncodeAndDecode() throws {
            let collection = SpaceCollection(
                id: .generate(),
                name: "Home",
                rows: [
                    SpacesRow(spaces: [
                        Space(
                            id: .generate(),
                            enabled: true,
                            displays: [
                                "0": LayoutGroup(
                                    name: "half split",
                                    layouts: [
                                        Layout(
                                            label: "Left",
                                            position: LayoutPosition(x: "0", y: "0"),
                                            size: LayoutSize(width: "50%", height: "100%")
                                        )
                                    ]
                                )
                            ]
                        )
                    ])
                ]
            )

            let encoded = try JSONEncoder().encode([collection])
            let decoded = try JSONDecoder().decode([SpaceCollection].self, from: encoded)
            #expect(decoded == [collection])
        }
    }
}
