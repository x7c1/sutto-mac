import Testing

@testable import SuttoDomain

/// Coverage for the pure edge-geometry check ported from the GNOME
/// `EdgeDetector`. A 100×80 rectangle at the origin with the default
/// threshold of 10 gives edges at x∈{0,100}, y∈{0,80}.
@Suite struct EdgeDetectorTests {
    private let rect = PixelRect(x: 0, y: 0, width: 100, height: 80)
    private let detector = EdgeDetector()

    @Test func thresholdDefaultsToTheGnomeConstant() {
        // EDGE_THRESHOLD = 10 in the GNOME version's controller.ts.
        #expect(EdgeDetector.defaultThreshold == 10)
        #expect(detector.threshold == 10)
    }

    @Test func pointAtEachOfTheFourEdgesIsDetected() {
        #expect(detector.isAtEdge(PixelPoint(x: 0, y: 40), of: rect)) // min-x
        #expect(detector.isAtEdge(PixelPoint(x: 100, y: 40), of: rect)) // max-x
        #expect(detector.isAtEdge(PixelPoint(x: 50, y: 0), of: rect)) // min-y
        #expect(detector.isAtEdge(PixelPoint(x: 50, y: 80), of: rect)) // max-y
    }

    @Test func eachOfTheFourCornersIsDetected() {
        #expect(detector.isAtEdge(PixelPoint(x: 0, y: 0), of: rect))
        #expect(detector.isAtEdge(PixelPoint(x: 100, y: 0), of: rect))
        #expect(detector.isAtEdge(PixelPoint(x: 0, y: 80), of: rect))
        #expect(detector.isAtEdge(PixelPoint(x: 100, y: 80), of: rect))
    }

    @Test func pointJustInsideTheThresholdIsDetected() {
        // 9 px in from each edge is within the 10 px threshold.
        #expect(detector.isAtEdge(PixelPoint(x: 9, y: 40), of: rect)) // near min-x
        #expect(detector.isAtEdge(PixelPoint(x: 91, y: 40), of: rect)) // near max-x
        #expect(detector.isAtEdge(PixelPoint(x: 50, y: 9), of: rect)) // near min-y
        #expect(detector.isAtEdge(PixelPoint(x: 50, y: 71), of: rect)) // near max-y
    }

    @Test func pointExactlyAtTheThresholdIsDetected() {
        // The boundary is inclusive (`<=` / `>=`).
        #expect(detector.isAtEdge(PixelPoint(x: 10, y: 40), of: rect))
        #expect(detector.isAtEdge(PixelPoint(x: 90, y: 40), of: rect))
        #expect(detector.isAtEdge(PixelPoint(x: 50, y: 10), of: rect))
        #expect(detector.isAtEdge(PixelPoint(x: 50, y: 70), of: rect))
    }

    @Test func pointJustOutsideTheThresholdIsNotDetected() {
        // 11 px in from every edge clears the threshold on all sides.
        #expect(!detector.isAtEdge(PixelPoint(x: 11, y: 40), of: rect))
        #expect(!detector.isAtEdge(PixelPoint(x: 89, y: 40), of: rect))
        #expect(!detector.isAtEdge(PixelPoint(x: 50, y: 11), of: rect))
        #expect(!detector.isAtEdge(PixelPoint(x: 50, y: 69), of: rect))
    }

    @Test func pointInTheCenterIsNotDetected() {
        #expect(!detector.isAtEdge(rect.center, of: rect))
        #expect(!detector.isAtEdge(PixelPoint(x: 50, y: 40), of: rect))
    }

    /// The detector compares raw numbers, so a rectangle with a non-zero
    /// (and negative) origin — as a secondary display has in AppKit global
    /// coordinates — is handled the same way.
    @Test func worksWithARectangleAtANonZeroOrigin() {
        let offset = PixelRect(x: -200, y: -100, width: 100, height: 80)
        #expect(detector.isAtEdge(PixelPoint(x: -200, y: -60), of: offset))
        #expect(detector.isAtEdge(PixelPoint(x: -100, y: -60), of: offset))
        #expect(!detector.isAtEdge(PixelPoint(x: -150, y: -60), of: offset))
    }

    @Test func honoursACustomThreshold() {
        let wide = EdgeDetector(threshold: 25)
        // 20 px in is outside the default 10 but inside a 25 px threshold.
        #expect(!detector.isAtEdge(PixelPoint(x: 20, y: 40), of: rect))
        #expect(wide.isAtEdge(PixelPoint(x: 20, y: 40), of: rect))
    }
}
