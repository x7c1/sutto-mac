import Testing

@testable import SuttoDomain

/// Direct tests of the boundary-robust screen selection
/// (``Screen/containing(_:in:)``) and the rect distance it relies on. All
/// frames are in AppKit coordinates (bottom-left origin, y up); see
/// ``ScreenFixtures`` for the arrangements.
///
/// The regression this pins down: on a laptop + external-monitor setup, a
/// point on the external screen's *exact* top/right edge used to resolve to
/// the primary (laptop) screen, because the half-open ``PixelRect/contains(_:)``
/// excludes the `maxX`/`maxY` edges and every selection site then fell back
/// to the primary. Selecting the nearest screen (distance 0 for a point on a
/// screen's boundary) keeps such a point on its own screen.
@Suite struct ScreenSelectionTests {
    @Suite struct Containing {
        @Test func returnsNilForNoScreens() {
            #expect(Screen.containing(PixelPoint(x: 0, y: 0), in: []) == nil)
        }

        @Test func resolvesAnInteriorPointToItsScreen() {
            let chosen = Screen.containing(
                PixelPoint(x: 2500, y: 400), in: ScreenFixtures.secondaryRight)
            #expect(chosen == ScreenFixtures.secondary(x: 1920, y: 0))
        }

        /// The shared edge between two adjacent screens stays deterministic:
        /// half-open containment gives it to the screen that *starts* there,
        /// not the one that ends there — unchanged by the nearest-screen
        /// fallback (which only runs when no screen contains the point).
        @Test func assignsTheSharedEdgeToTheStartingScreenViaContainment() {
            // Primary maxX = 1920 = secondary minX. The point at x = 1920 is
            // outside the primary (half-open) but inside the secondary.
            let chosen = Screen.containing(
                PixelPoint(x: 1920, y: 400), in: ScreenFixtures.secondaryRight)
            #expect(chosen == ScreenFixtures.secondary(x: 1920, y: 0))
        }

        /// The bug: the exact top edge of a secondary stacked above the
        /// primary (`y == frame.maxY = 1980`) is contained by no screen, and
        /// must resolve to the secondary — the nearest screen (distance 0) —
        /// not the primary.
        @Test func resolvesTheSecondaryTopEdgeToTheSecondaryNotThePrimary() {
            let chosen = Screen.containing(
                PixelPoint(x: 800, y: 1980), in: ScreenFixtures.stackedAbove)
            #expect(chosen == ScreenFixtures.secondary(x: 0, y: 1080))
        }

        /// The same failure on the right edge: the exact right column of a
        /// secondary to the right of the primary (`x == frame.maxX = 3520`)
        /// resolves to that secondary.
        @Test func resolvesTheSecondaryRightEdgeToTheSecondaryNotThePrimary() {
            let chosen = Screen.containing(
                PixelPoint(x: 3520, y: 400), in: ScreenFixtures.secondaryRight)
            #expect(chosen == ScreenFixtures.secondary(x: 1920, y: 0))
        }

        /// The primary's own top edge was never affected (its fallback was
        /// itself), and stays on the primary here as a control.
        @Test func resolvesThePrimaryTopEdgeToThePrimary() {
            // Single primary (0, 0, 1920, 1080): its top edge is y = 1080.
            let chosen = Screen.containing(
                PixelPoint(x: 960, y: 1080), in: ScreenFixtures.single)
            #expect(chosen == ScreenFixtures.primary)
        }

        /// A point off every screen resolves to the nearest one — and the
        /// nearest can be a non-primary screen, proving there is no blind
        /// primary fallback.
        @Test func resolvesAnOffScreenPointToTheNearestScreen() {
            // Far to the left of the left-secondary (-1600, 0, 1600, 900):
            // nearer it than the primary at x = 0.
            let chosen = Screen.containing(
                PixelPoint(x: -5000, y: 400), in: ScreenFixtures.secondaryLeft)
            #expect(chosen == ScreenFixtures.secondary(x: -1600, y: 0))
        }
    }

    @Suite struct RectDistance {
        private let rect = PixelRect(x: 0, y: 0, width: 100, height: 100)

        @Test func isZeroForAnInteriorPoint() {
            #expect(rect.distance(to: PixelPoint(x: 50, y: 50)) == 0)
        }

        @Test func isZeroForAPointOnTheMaxEdges() {
            // The half-open contains(_:) excludes these, but distance treats
            // the closed boundary as distance 0 — the crux of the fix.
            #expect(rect.distance(to: PixelPoint(x: 100, y: 50)) == 0)
            #expect(rect.distance(to: PixelPoint(x: 50, y: 100)) == 0)
            #expect(rect.distance(to: PixelPoint(x: 100, y: 100)) == 0)
        }

        @Test func isThePerpendicularGapOffASingleAxis() {
            #expect(rect.distance(to: PixelPoint(x: 130, y: 50)) == 30)
            #expect(rect.distance(to: PixelPoint(x: 50, y: -20)) == 20)
        }

        @Test func isTheDiagonalGapOffACorner() {
            // (103, 104) is (3, 4) beyond the (100, 100) corner → 5.
            #expect(rect.distance(to: PixelPoint(x: 103, y: 104)) == 5)
        }
    }
}
