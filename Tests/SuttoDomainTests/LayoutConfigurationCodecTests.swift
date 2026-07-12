import Foundation
import Testing

@testable import SuttoDomain

/// Loads a fixture from Tests/SuttoDomainTests/Fixtures by base name.
private func fixtureData(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
        "missing fixture \(name).json")
    return try Data(contentsOf: url)
}

private func decodeConfiguration(_ data: Data) throws -> LayoutConfiguration {
    try JSONDecoder().decode(LayoutConfiguration.self, from: data)
}

/// JSON codec tests for ``LayoutConfiguration``, the user-facing import
/// format. Cross-OS compatibility is the point: a document a user feeds to
/// the GNOME version must decode identically here.
///
/// The fixtures in Tests/SuttoDomainTests/Fixtures are real sample
/// collections vendored verbatim from the GNOME version's `docs/examples/`
/// directory (github.com/x7c1/sutto, commit f5860f5, GPLv3 like this
/// repository) — genuine documents the GNOME import accepts, not
/// hand-crafted approximations.
@Suite struct LayoutConfigurationCodecTests {
    /// Every sample shipped in the GNOME repository's docs/examples/.
    private static let fixtureNames = [
        "dev-triple-monitor",
        "dual-wide-monitors",
        "overlap-tests",
        "single-wide-monitor",
        "streaming-setup",
        "ultrawide-productivity",
    ]

    @Suite struct Fixtures {
        @Test(arguments: LayoutConfigurationCodecTests.fixtureNames)
        func decodes(fixture: String) throws {
            let configuration = try decodeConfiguration(fixtureData(fixture))
            // Mirrors `isValidLayoutConfiguration` in the GNOME
            // import-collection.ts: a real document always carries a
            // non-empty name and at least one layout group.
            #expect(!configuration.name.isEmpty)
            #expect(!configuration.layoutGroups.isEmpty)
            #expect(!configuration.rows.isEmpty)
        }

        @Test(arguments: LayoutConfigurationCodecTests.fixtureNames)
        func reencodedFixtureIsStructurallyEqualToTheOriginal(fixture: String) throws {
            let data = try fixtureData(fixture)
            let configuration = try decodeConfiguration(data)
            let encoded = try JSONEncoder().encode(configuration)

            let original = try #require(
                try JSONSerialization.jsonObject(with: data) as? NSDictionary)
            let reencoded = try #require(
                try JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
            #expect(original == reencoded)
        }

        /// Spot-checks exact values of the simplest fixture, so a decode
        /// that silently mangles fields cannot hide behind the structural
        /// comparison.
        @Test func decodesSingleWideMonitorExactly() throws {
            let configuration = try decodeConfiguration(fixtureData("single-wide-monitor"))

            #expect(configuration.name == "Single Monitor Basic")
            #expect(configuration.layoutGroups.map(\.name) == ["half split", "full"])

            let halfSplit = configuration.layoutGroups[0]
            #expect(
                halfSplit.layouts == [
                    LayoutSetting(label: "Left", x: "0", y: "0", width: "50%", height: "100%"),
                    LayoutSetting(label: "Right", x: "50%", y: "0", width: "50%", height: "100%"),
                ])

            #expect(configuration.rows.count == 1)
            #expect(
                configuration.rows[0].spaces == [
                    SpaceSetting(displays: ["0": "half split"]),
                    SpaceSetting(displays: ["0": "full"]),
                ])
        }

        /// The triple-monitor fixture pins multi-display keys ("0"/"1"/"2")
        /// mapping to layout group names.
        @Test func decodesMultiMonitorDisplayAssignments() throws {
            let configuration = try decodeConfiguration(fixtureData("dev-triple-monitor"))

            #expect(configuration.rows.count == 2)
            #expect(
                configuration.rows[0].spaces == [
                    SpaceSetting(displays: [
                        "0": "chat + docs",
                        "1": "editor + terminal",
                        "2": "browser + devtools",
                    ])
                ])
        }
    }

    @Suite struct Tolerance {
        @Test func ignoresUnknownFields() throws {
            // The GNOME importer runs JSON.parse plus a shallow validator
            // (`isValidLayoutConfiguration`), so unknown fields pass
            // through; the Swift decoder must be at least as tolerant.
            let json = """
                {
                  "name": "Minimal",
                  "comment": "not part of the schema",
                  "layoutGroups": [],
                  "rows": []
                }
                """
            let configuration = try decodeConfiguration(Data(json.utf8))
            #expect(configuration.name == "Minimal")
        }
    }

    @Suite struct DecodingFailures {
        @Test func rejectsAMissingName() {
            // `isValidLayoutConfiguration` requires `name` to be a string.
            let json = #"{"layoutGroups": [], "rows": []}"#
            #expect(throws: DecodingError.self) {
                try decodeConfiguration(Data(json.utf8))
            }
        }

        @Test func rejectsMissingLayoutGroups() {
            let json = #"{"name": "Work", "rows": []}"#
            #expect(throws: DecodingError.self) {
                try decodeConfiguration(Data(json.utf8))
            }
        }

        @Test func rejectsMissingRows() {
            let json = #"{"name": "Work", "layoutGroups": []}"#
            #expect(throws: DecodingError.self) {
                try decodeConfiguration(Data(json.utf8))
            }
        }

        @Test func rejectsANonStringExpression() {
            // The GNOME validator is shallow, so `"x": 0` (number instead
            // of string) slips into the conversion and produces a broken
            // layout; the Swift decoder rejects the document up front. The
            // net effect on a valid document is identical, and no valid
            // document uses non-string expressions.
            let json = """
                {
                  "name": "Broken",
                  "layoutGroups": [
                    {
                      "name": "g",
                      "layouts": [
                        { "label": "L", "x": 0, "y": "0", "width": "50%", "height": "100%" }
                      ]
                    }
                  ],
                  "rows": []
                }
                """
            #expect(throws: DecodingError.self) {
                try decodeConfiguration(Data(json.utf8))
            }
        }
    }
}
