import Testing

@testable import SuttoDomain

/// The wide-vs-standard classification rule: wide iff the aspect ratio is
/// at least 21:9. The GNOME version documents this rule in its
/// `preset-config.ts` ("aspect ratio >= 21:9") but leaves the choice between
/// the generated presets to the user; the mac app applies the rule directly,
/// so the boundary is pinned here.
@Suite struct MonitorTypeTests {
    @Test func standardAspectRatiosAreStandard() {
        // 16:9, 16:10, 4:3 — everyday landscape displays.
        #expect(MonitorType.classify(width: 1920, height: 1080) == .standard)
        #expect(MonitorType.classify(width: 2560, height: 1600) == .standard)
        #expect(MonitorType.classify(width: 1024, height: 768) == .standard)
    }

    @Test func ultrawideAspectRatiosAreWide() {
        // 21:9-class (3440x1440 is 21.5:9) and 32:9 super-ultrawide.
        #expect(MonitorType.classify(width: 3440, height: 1440) == .wide)
        #expect(MonitorType.classify(width: 5120, height: 1440) == .wide)
    }

    /// Exactly 21:9 is wide: the rule is ">= 21:9", inclusive.
    @Test func theExactBoundaryIsWide() {
        #expect(MonitorType.classify(width: 2520, height: 1080) == .wide)
        #expect(MonitorType.classify(width: 21, height: 9) == .wide)
    }

    /// One pixel narrower than 21:9 falls back to standard.
    @Test func justBelowTheBoundaryIsStandard() {
        #expect(MonitorType.classify(width: 2519, height: 1080) == .standard)
    }

    @Test func portraitOrientationsAreStandard() {
        #expect(MonitorType.classify(width: 1080, height: 1920) == .standard)
        // Even a rotated ultrawide reads as standard: 1440x3440.
        #expect(MonitorType.classify(width: 1440, height: 3440) == .standard)
    }

    @Test func degenerateSizesAreStandard() {
        #expect(MonitorType.classify(width: 1920, height: 0) == .standard)
        #expect(MonitorType.classify(width: 0, height: 0) == .standard)
    }
}
