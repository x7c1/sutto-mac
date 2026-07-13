import Testing

@testable import SuttoDomain

/// A mouse position on the primary screen. Used wherever the test wants to
/// prove that the *anchor's* screen wins over the mouse's screen — and, in
/// the fallback tests, that the mouse's screen wins over the primary.
private let mouseOnPrimary = PixelPoint(x: 100, y: 100)

/// The panel size used throughout: small enough to fit every fixture work
/// area with room to spare, so only the edge tests trigger clamping.
private let panelWidth = 600.0
private let panelHeight = 300.0

/// Everything is in AppKit coordinates (bottom-left origin, y up); see
/// ``ScreenFixtures`` for the arrangements. The GNOME-ported rules under
/// test: panel centered on the anchor in both axes, clamped into the
/// anchor screen's work area inset by the 10 px edge padding, left/top
/// edges winning when the panel does not fit.
@Suite struct PanelPositionResolverTests {
    @Suite struct CenteredOnTheAnchor {
        @Test func centersThePanelOnTheAnchorInBothAxes() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 500),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 660, y: 350, width: 600, height: 300))
        }

        @Test func returnsNilWithoutScreens() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 500),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: [],
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == nil)
        }
    }

    @Suite struct ClampedAtTheEdges {
        // The primary work area is (0, 0, 1920, 1055): padded x range
        // [10, 1310] for a 600-wide panel, padded y range [10, 745] for a
        // 300-tall panel.

        @Test func clampsToTheLeftEdge() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 50, y: 500),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 10, y: 350, width: 600, height: 300))
        }

        @Test func clampsToTheRightEdge() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 1900, y: 500),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 1310, y: 350, width: 600, height: 300))
        }

        @Test func clampsToTheBottomEdge() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 20),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 660, y: 10, width: 600, height: 300))
        }

        /// The work area's top edge is 1055 (the menu bar trims the high-y
        /// side), so the highest allowed origin is 1055 - 10 - 300 = 745 —
        /// the panel stays clear of the menu bar, not just the screen.
        @Test func clampsToTheWorkAreaTopBelowTheMenuBar() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 1050),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 660, y: 745, width: 600, height: 300))
        }

        /// A corner window clamps on both axes at once.
        @Test func clampsBothAxesInACorner() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 1919, y: 1),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 1310, y: 10, width: 600, height: 300))
        }

        /// GNOME clamp order ported: when the panel is larger than the
        /// padded work area, the left and top edges win, keeping the
        /// panel's top-left corner visible at the padding inset. The top
        /// edge at 1055 - 10 puts the origin at 1045 - height.
        @Test func pinsLeftAndTopEdgesWhenThePanelDoesNotFit() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 500),
                panelWidth: 2400,
                panelHeight: 1600,
                screens: ScreenFixtures.single,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 10, y: 1045 - 1600, width: 2400, height: 1600))
        }
    }

    @Suite struct AcrossScreens {
        /// A window straddling the primary/secondary boundary belongs to
        /// the screen containing its *center* — the anchor. Center on the
        /// secondary → clamped inside the secondary's work area
        /// ((1920, 0, 1600, 875): padded x range [1930, 2910]).
        @Test func clampsWithinTheScreenContainingTheAnchor() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 1950, y: 500),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.secondaryRight,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 1930, y: 350, width: 600, height: 300))
        }

        /// Negative-coordinate arrangement: the secondary sits left of the
        /// primary at x = -1600 (work area (-1600, 0, 1600, 875), padded x
        /// range [-1590, -610]).
        @Test func clampsWithinANegativeCoordinateScreen() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: -1580, y: 400),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.secondaryLeft,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: -1590, y: 250, width: 600, height: 300))
        }

        /// A screen below the primary has negative y (work area
        /// (0, -900, 1600, 875), padded y range [-890, -335]).
        @Test func clampsWithinAScreenBelowThePrimary() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 800, y: -880),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.stackedBelow,
                mouseLocation: mouseOnPrimary
            )
            #expect(frame == PixelRect(x: 500, y: -890, width: 600, height: 300))
        }
    }

    @Suite struct OffScreenAnchorFallback {
        /// An anchor on no screen (a window dragged mostly off-screen can
        /// have an off-screen center) falls back to the mouse's screen —
        /// here the secondary — and clamps the anchor-centered rect into
        /// its work area.
        @Test func fallsBackToTheMouseScreen() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 5000, y: 5000),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.secondaryRight,
                mouseLocation: PixelPoint(x: 2000, y: 400)
            )
            // Secondary work area (1920, 0, 1600, 875): the far-off anchor
            // clamps to the right/top corner of the padded area
            // (x 1920 + 1600 - 10 - 600 = 2910, y 875 - 10 - 300 = 565).
            #expect(frame == PixelRect(x: 2910, y: 565, width: 600, height: 300))
        }

        /// Mouse off-screen too → the primary clamps.
        @Test func fallsBackToThePrimaryWhenTheMouseIsOffScreenToo() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 5000, y: 5000),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.secondaryRight,
                mouseLocation: PixelPoint(x: -5000, y: -5000)
            )
            #expect(frame == PixelRect(x: 1310, y: 745, width: 600, height: 300))
        }
    }
}
