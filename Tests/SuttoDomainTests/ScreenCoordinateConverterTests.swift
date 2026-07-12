import Testing

@testable import SuttoDomain

/// The primary screen is 1920x1080 at AppKit origin (0, 0), so the mirror
/// line for every conversion below is `primary.maxY = 1080`:
/// `axY = 1080 - (appKitY + height)` and vice versa. Every known-answer
/// value in these tests is hand-computed from that formula in the comments.
@Suite struct ScreenCoordinateConverterTests {
    private let primaryFrame = ScreenFixtures.primary.frame

    @Suite struct KnownAnswersOnThePrimaryScreen {
        private let primaryFrame = ScreenFixtures.primary.frame

        @Test func convertsAWindowAtTheTopLeftCorner() {
            // A window hugging the primary's top-left corner: AppKit
            // y = 1080 - 600 = 480 puts its top edge at 1080, and in AX
            // space the top-left corner is the origin, so y = 0.
            // Check: axY = 1080 - (480 + 600) = 0.
            let appKit = PixelRect(x: 0, y: 480, width: 800, height: 600)
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: appKit, primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: 0, y: 0, width: 800, height: 600))
        }

        @Test func convertsAWindowAtTheBottomLeftCorner() {
            // A window at the AppKit origin has its top edge at y = 600,
            // which is 1080 - 600 = 480 below the primary's top edge.
            let appKit = PixelRect(x: 0, y: 0, width: 800, height: 600)
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: appKit, primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: 0, y: 480, width: 800, height: 600))
        }

        @Test func convertsThePrimaryFrameToTheAXOrigin() {
            // The primary screen itself starts at the AX origin by
            // definition: axY = 1080 - (0 + 1080) = 0.
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: primaryFrame, primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: 0, y: 0, width: 1920, height: 1080))
        }

        @Test func convertsThePrimaryWorkAreaBelowTheMenuBar() {
            // The 25 px menu bar trims the high-y side in AppKit (visible
            // frame 1920x1055 at y = 0), which in AX space means the work
            // area starts 25 px below the top: axY = 1080 - (0 + 1055) = 25.
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: ScreenFixtures.primary.visibleFrame,
                primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: 0, y: 25, width: 1920, height: 1055))
        }
    }

    @Suite struct KnownAnswersOnSecondaryScreens {
        private let primaryFrame = ScreenFixtures.primary.frame

        @Test func convertsASecondaryToTheRight() {
            // Bottom-aligned 1600x900 at x = 1920. Being 180 px shorter than
            // the primary, its top edge sits 180 px below the primary's top:
            // axY = 1080 - (0 + 900) = 180. x passes through unchanged.
            let screen = ScreenFixtures.secondary(x: 1920, y: 0)
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: screen.frame, primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: 1920, y: 180, width: 1600, height: 900))
        }

        @Test func convertsASecondaryToTheLeftWithNegativeX() {
            // Same as the right-hand case, mirrored: x = -1600 stays
            // negative in AX space. axY = 1080 - (0 + 900) = 180.
            let screen = ScreenFixtures.secondary(x: -1600, y: 0)
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: screen.frame, primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: -1600, y: 180, width: 1600, height: 900))
        }

        @Test func convertsASecondaryStackedAbove() {
            // Above the primary means larger y in AppKit (y = 1080) but
            // *negative* y in AX space: axY = 1080 - (1080 + 900) = -900.
            let screen = ScreenFixtures.secondary(x: 0, y: 1080)
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: screen.frame, primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: 0, y: -900, width: 1600, height: 900))
        }

        @Test func convertsASecondaryStackedBelowWithNegativeY() {
            // Below the primary means negative y in AppKit (y = -900) and
            // positive y in AX space: axY = 1080 - (-900 + 900) = 1080 — its
            // top edge starts exactly where the primary ends.
            let screen = ScreenFixtures.secondary(x: 0, y: -900)
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: screen.frame, primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: 0, y: 1080, width: 1600, height: 900))
        }

        @Test func convertsASecondaryBelowAndLeftWithBothNegative() {
            // Both offsets at once: x = -1600 passes through, and
            // axY = 1080 - (-900 + 900) = 1080 as in the stacked-below case.
            let screen = ScreenFixtures.secondary(x: -1600, y: -900)
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: screen.frame, primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: -1600, y: 1080, width: 1600, height: 900))
        }

        @Test func convertsAWindowOnTheStackedBelowScreen() {
            // A 800x600 window on the below screen at AppKit (100, -720):
            // axY = 1080 - (-720 + 600) = 1200, i.e. 120 px below that
            // screen's AX top edge of 1080.
            let appKit = PixelRect(x: 100, y: -720, width: 800, height: 600)
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: appKit, primaryScreenFrame: primaryFrame)
            #expect(ax == PixelRect(x: 100, y: 1200, width: 800, height: 600))
        }
    }

    @Suite struct Inverse {
        private let primaryFrame = ScreenFixtures.primary.frame

        @Test func convertsAnAXRectBackToAppKit() {
            // Inverse of the top-left window case: appKitY =
            // 1080 - (0 + 600) = 480.
            let ax = PixelRect(x: 0, y: 0, width: 800, height: 600)
            let appKit = ScreenCoordinateConverter.appKitRect(
                fromAX: ax, primaryScreenFrame: primaryFrame)
            #expect(appKit == PixelRect(x: 0, y: 480, width: 800, height: 600))
        }
    }

    @Suite struct RoundTrips {
        /// Rectangles spanning all screens of every fixture arrangement,
        /// including fully negative origins and fractional coordinates.
        static let rects = [
            PixelRect(x: 0, y: 0, width: 800, height: 600),
            PixelRect(x: 2000, y: 100, width: 640, height: 480),
            PixelRect(x: -1500, y: 200, width: 640, height: 480),
            PixelRect(x: 100, y: 1200, width: 640, height: 480),
            PixelRect(x: -1200, y: -800, width: 640, height: 480),
            PixelRect(x: 0.5, y: -0.25, width: 333.25, height: 777.75),
        ]

        @Test(arguments: ScreenFixtures.allConfigurations, rects)
        func appKitToAXAndBackIsIdentity(screens: [Screen], rect: PixelRect) {
            let primaryFrame = screens[0].frame
            let ax = ScreenCoordinateConverter.axRect(
                fromAppKit: rect, primaryScreenFrame: primaryFrame)
            let back = ScreenCoordinateConverter.appKitRect(
                fromAX: ax, primaryScreenFrame: primaryFrame)
            #expect(back == rect)
        }

        @Test(arguments: ScreenFixtures.allConfigurations, rects)
        func axToAppKitAndBackIsIdentity(screens: [Screen], rect: PixelRect) {
            let primaryFrame = screens[0].frame
            let appKit = ScreenCoordinateConverter.appKitRect(
                fromAX: rect, primaryScreenFrame: primaryFrame)
            let back = ScreenCoordinateConverter.axRect(
                fromAppKit: appKit, primaryScreenFrame: primaryFrame)
            #expect(back == rect)
        }
    }
}
