import Testing

@testable import SuttoDomain

private let leftHalf = Layout(
    label: "Left Half",
    position: LayoutPosition(x: "0", y: "0"),
    size: LayoutSize(width: "50%", height: "100%")
)

private let rightHalf = Layout(
    label: "Right Half",
    position: LayoutPosition(x: "50%", y: "0"),
    size: LayoutSize(width: "50%", height: "100%")
)

private let bottomHalf = Layout(
    label: "Bottom Half",
    position: LayoutPosition(x: "0", y: "50%"),
    size: LayoutSize(width: "100%", height: "50%")
)

/// A mouse position on the primary screen. Used wherever the test wants to
/// prove that the *window's* screen wins over the mouse's screen.
private let mouseOnPrimary = PixelPoint(x: 100, y: 100)

/// Every expected frame below is hand-computed. The recurring ingredients
/// (from ``ScreenFixtures``, primary maxY = 1080):
///
/// - primary work area (0, 0, 1920, 1055) → AX y = 1080 - 1055 = 25,
///   so the AX work area is (0, 25, 1920, 1055)
/// - a secondary work area of height 875 at AppKit y = 0 → AX y =
///   1080 - 875 = 205
/// - the stacked-above work area (0, 1080, 1600, 875) → AX y =
///   1080 - (1080 + 875) = -875
/// - the stacked-below work area (0, -900, 1600, 875) → AX y =
///   1080 - (-900 + 875) = 1105 (same for below-and-left)
@Suite struct PlacementFrameResolverTests {
    @Suite struct OnThePrimaryScreen {
        // Window at AX (200, 200, 800, 600): AppKit y = 1080 - 800 = 280,
        // center (600, 580) — on the primary.
        private let windowOnPrimary = PixelRect(x: 200, y: 200, width: 800, height: 600)

        @Test func resolvesLeftHalfAgainstThePrimaryWorkArea() throws {
            // Left half of the AX work area (0, 25, 1920, 1055):
            // width 50% of 1920 = 960, full height.
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: windowOnPrimary,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 0, y: 25, width: 960, height: 1055))
        }

        @Test func resolvesRightHalfWithTheHorizontalOffset() throws {
            // x = 50% of 1920 = 960 from the work-area left edge.
            let frame = try PlacementFrameResolver.resolve(
                layout: rightHalf,
                windowFrame: windowOnPrimary,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 960, y: 25, width: 960, height: 1055))
        }

        @Test func resolvesBottomHalfDownwardFromTheWorkAreaTop() throws {
            // Layout y offsets grow downward from the work-area top, which
            // matches AX orientation: 50% of 1055 = 527.5, rounded like
            // JavaScript's Math.round (ties toward +∞) to 528 for both the
            // offset and the height. AX y = 25 + 528 = 553.
            let frame = try PlacementFrameResolver.resolve(
                layout: bottomHalf,
                windowFrame: windowOnPrimary,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 0, y: 553, width: 1920, height: 528))
        }
    }

    @Suite struct AcrossMonitorArrangements {
        @Test func resolvesOnTheSecondaryToTheRight() throws {
            // Window at AX (2000, 300, 800, 600): AppKit y = 1080 - 900 =
            // 180, center (2400, 480) — on the right secondary. Its AX work
            // area is (1920, 205, 1600, 875); left half is 800 wide.
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: PixelRect(x: 2000, y: 300, width: 800, height: 600),
                screens: ScreenFixtures.secondaryRight,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 1920, y: 205, width: 800, height: 875))
        }

        @Test func resolvesOnTheSecondaryToTheLeftWithNegativeX() throws {
            // Window at AX (-1500, 300, 800, 600): center (-1100, 480) — on
            // the left secondary. Its AX work area is (-1600, 205, 1600, 875).
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: PixelRect(x: -1500, y: 300, width: 800, height: 600),
                screens: ScreenFixtures.secondaryLeft,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: -1600, y: 205, width: 800, height: 875))
        }

        @Test func resolvesOnTheScreenStackedAbove() throws {
            // Window at AX (100, -800, 800, 600): AppKit y = 1080 - (-800 +
            // 600) = 1280, center (500, 1580) — on the screen above. Its AX
            // work area is (0, -875, 1600, 875), entirely at negative AX y.
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: PixelRect(x: 100, y: -800, width: 800, height: 600),
                screens: ScreenFixtures.stackedAbove,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 0, y: -875, width: 800, height: 875))
        }

        @Test func resolvesOnTheScreenStackedBelowWithNegativeAppKitY() throws {
            // Window at AX (100, 1200, 800, 600): AppKit y = 1080 - 1800 =
            // -720, center (500, -420) — on the screen below. Its AX work
            // area is (0, 1105, 1600, 875).
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: PixelRect(x: 100, y: 1200, width: 800, height: 600),
                screens: ScreenFixtures.stackedBelow,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 0, y: 1105, width: 800, height: 875))
        }

        @Test func resolvesOnTheScreenBelowAndLeftWithBothNegative() throws {
            // Window at AX (-1500, 1200, 800, 600): AppKit (-1500, -720),
            // center (-1100, -420) — on the below-and-left screen. Its AX
            // work area is (-1600, 1105, 1600, 875).
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: PixelRect(x: -1500, y: 1200, width: 800, height: 600),
                screens: ScreenFixtures.belowAndLeft,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: -1600, y: 1105, width: 800, height: 875))
        }

        @Test func assignsACenterOnTheSharedEdgeToExactlyOneScreen() throws {
            // Window straddling the primary/right-secondary edge: AX (1520,
            // 380, 800, 600) → AppKit y = 1080 - 980 = 100, center exactly
            // at (1920, 400). Containment is half-open, so the center
            // belongs to the secondary starting at x = 1920, not the
            // primary ending there.
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: PixelRect(x: 1520, y: 380, width: 800, height: 600),
                screens: ScreenFixtures.secondaryRight,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 1920, y: 205, width: 800, height: 875))
        }
    }

    @Suite struct ScreenSelectionFallbacks {
        // A window whose center is on no screen: AX (10000, 10000, 100,
        // 100) → AppKit y = 1080 - 10100 = -9020, center (10050, -8970) —
        // far off every fixture arrangement.
        private let offScreenWindow = PixelRect(x: 10000, y: 10000, width: 100, height: 100)

        @Test func prefersTheWindowScreenOverTheMouseScreen() throws {
            // Window on the right secondary, mouse on the primary: the
            // window's screen wins, so the frame targets the secondary.
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: PixelRect(x: 2000, y: 300, width: 800, height: 600),
                screens: ScreenFixtures.secondaryRight,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 1920, y: 205, width: 800, height: 875))
        }

        @Test func fallsBackToTheMouseScreenWhenTheCenterIsOffScreen() throws {
            // Mouse at AppKit (-800, 450) — on the left secondary, whose AX
            // work area is (-1600, 205, 1600, 875).
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: offScreenWindow,
                screens: ScreenFixtures.secondaryLeft,
                mouseLocation: PixelPoint(x: -800, y: 450)
            )
            #expect(frame == PixelRect(x: -1600, y: 205, width: 800, height: 875))
        }

        @Test func fallsBackToThePrimaryWhenTheMouseIsAlsoOffScreen() throws {
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: offScreenWindow,
                screens: ScreenFixtures.secondaryLeft,
                mouseLocation: PixelPoint(x: 99999, y: 99999)
            )
            #expect(frame == PixelRect(x: 0, y: 25, width: 960, height: 1055))
        }
    }

    @Suite struct EdgeCases {
        @Test func returnsNilWithoutScreens() throws {
            let frame = try PlacementFrameResolver.resolve(
                layout: leftHalf,
                windowFrame: PixelRect(x: 0, y: 0, width: 800, height: 600),
                screens: [],
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == nil)
        }

        @Test func propagatesInvalidLayoutExpressions() {
            let broken = Layout(
                label: "broken",
                position: LayoutPosition(x: "abc", y: "0"),
                size: LayoutSize(width: "50%", height: "100%")
            )
            #expect(throws: LayoutExpressionParseError.invalidTerm("abc")) {
                try PlacementFrameResolver.resolve(
                    layout: broken,
                    windowFrame: PixelRect(x: 0, y: 0, width: 800, height: 600),
                    screens: ScreenFixtures.single,
                    mouseLocation: mouseOnPrimary
                )
            }
        }
    }
}
