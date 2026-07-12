import Testing

@testable import SuttoDomain

/// Tests for `LayoutConfiguration.validate()`, the Swift counterpart of
/// `isValidLayoutConfiguration` in the GNOME `import-collection.ts`. The
/// GNOME repository ships no tests for that validator, so these are derived
/// from its branches: the structural checks are covered by `Codable`
/// decoding (see `LayoutConfigurationCodecTests`), leaving the empty-name
/// rejection (`config.name.trim() === ''`) as the semantic rule under test.
@Suite struct LayoutConfigurationValidationTests {
    private func makeConfiguration(name: String) -> LayoutConfiguration {
        LayoutConfiguration(
            name: name,
            layoutGroups: [
                LayoutGroupSetting(
                    name: "half split",
                    layouts: [
                        LayoutSetting(label: "Left", x: "0", y: "0", width: "50%", height: "100%")
                    ]
                )
            ],
            rows: [
                SpacesRowSetting(spaces: [SpaceSetting(displays: ["0": "half split"])])
            ]
        )
    }

    @Test func acceptsANamedConfiguration() throws {
        try makeConfiguration(name: "Work").validate()
    }

    @Test func rejectsAnEmptyName() {
        #expect(throws: LayoutConfigurationValidationError.self) {
            try makeConfiguration(name: "").validate()
        }
    }

    /// The GNOME check trims first, so a whitespace-only name is as invalid
    /// as an empty one.
    @Test(arguments: [" ", "   ", "\t", "\n", " \t\n "])
    func rejectsAWhitespaceOnlyName(name: String) {
        #expect(throws: LayoutConfigurationValidationError.self) {
            try makeConfiguration(name: name).validate()
        }
    }

    /// A name with surrounding whitespace around real content is fine — the
    /// trim only guards against effectively-empty names, it does not reject
    /// padded ones.
    @Test func acceptsANameWithSurroundingWhitespace() throws {
        try makeConfiguration(name: "  Work  ").validate()
    }

    /// Empty groups and rows are accepted, matching the GNOME validator,
    /// which only requires them to be arrays.
    @Test func acceptsEmptyGroupsAndRows() throws {
        try LayoutConfiguration(name: "Empty", layoutGroups: [], rows: []).validate()
    }
}
