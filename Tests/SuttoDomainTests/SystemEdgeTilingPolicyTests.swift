import Testing

@testable import SuttoDomain

@Suite struct SystemEdgeTilingPolicyTests {
    @Test func explicitlyOnReadsAsEnabled() {
        #expect(SystemEdgeTilingPolicy.isEnabled(from: true))
    }

    @Test func explicitlyOffReadsAsDisabled() {
        #expect(!SystemEdgeTilingPolicy.isEnabled(from: false))
    }

    /// The key is absent until the user first toggles it, yet the OS still
    /// tiles by default on Sequoia — so a missing value must read as enabled.
    @Test func absentValueReadsAsEnabled() {
        #expect(SystemEdgeTilingPolicy.isEnabled(from: nil))
    }
}
