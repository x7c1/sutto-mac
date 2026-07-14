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

    // MARK: - conflicts(edgeTilingRawValue:menuBarFillRawValue:)

    /// The "absent → enabled" rule is applied per key, independently.
    @Test func conflictsInterpretsEachKeyIndependently() {
        // Both explicitly on.
        #expect(
            SystemEdgeTilingPolicy.conflicts(edgeTilingRawValue: true, menuBarFillRawValue: true)
                == EdgeTilingConflicts(edgeTiling: true, menuBarFill: true)
        )
        // Both explicitly off.
        #expect(
            SystemEdgeTilingPolicy.conflicts(edgeTilingRawValue: false, menuBarFillRawValue: false)
                == EdgeTilingConflicts(edgeTiling: false, menuBarFill: false)
        )
        // Absent reads as enabled, per key.
        #expect(
            SystemEdgeTilingPolicy.conflicts(edgeTilingRawValue: nil, menuBarFillRawValue: false)
                == EdgeTilingConflicts(edgeTiling: true, menuBarFill: false)
        )
        #expect(
            SystemEdgeTilingPolicy.conflicts(edgeTilingRawValue: false, menuBarFillRawValue: nil)
                == EdgeTilingConflicts(edgeTiling: false, menuBarFill: true)
        )
    }

    // MARK: - EdgeTilingConflicts.any

    @Test func anyIsTrueIffEitherGestureEnabled() {
        #expect(!EdgeTilingConflicts(edgeTiling: false, menuBarFill: false).any)
        #expect(EdgeTilingConflicts(edgeTiling: true, menuBarFill: false).any)
        #expect(EdgeTilingConflicts(edgeTiling: false, menuBarFill: true).any)
        #expect(EdgeTilingConflicts(edgeTiling: true, menuBarFill: true).any)
    }
}
