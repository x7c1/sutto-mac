import Testing

@testable import SuttoDomain

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
                screens: ScreenFixtures.single
            )
            #expect(frame == PixelRect(x: 660, y: 350, width: 600, height: 300))
        }

        @Test func returnsNilWithoutScreens() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 500),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: []            )
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
                screens: ScreenFixtures.single
            )
            #expect(frame == PixelRect(x: 10, y: 350, width: 600, height: 300))
        }

        @Test func clampsToTheRightEdge() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 1900, y: 500),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.single
            )
            #expect(frame == PixelRect(x: 1310, y: 350, width: 600, height: 300))
        }

        @Test func clampsToTheBottomEdge() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 20),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.single
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
                screens: ScreenFixtures.single
            )
            #expect(frame == PixelRect(x: 660, y: 745, width: 600, height: 300))
        }

        /// A corner window clamps on both axes at once.
        @Test func clampsBothAxesInACorner() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 1919, y: 1),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.single
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
                screens: ScreenFixtures.single
            )
            #expect(frame == PixelRect(x: 10, y: 1045 - 1600, width: 2400, height: 1600))
        }
    }

    /// The edge-trigger path anchors the panel's *top edge* at the anchor
    /// (the cursor) and keeps the horizontal centering, so the panel hangs
    /// below the cursor. The work-area clamp is identical to the centered
    /// path.
    @Suite struct TopAnchored {
        @Test func anchorsTheTopEdgeAtTheAnchorAndCentersHorizontally() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 500),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                verticalAnchor: .top,
                screens: ScreenFixtures.single
            )
            // x centered (960 − 300 = 660); origin.y = 500 − 300 = 200 so
            // the top edge (200 + 300) lands on the anchor's y = 500.
            #expect(frame == PixelRect(x: 660, y: 200, width: 600, height: 300))
            #expect(frame!.y + frame!.height == 500)
        }

        /// A high-y anchor (cursor near the work-area top) would push the
        /// panel off the top, so the top-edge clamp pins it at 745.
        @Test func clampsToTheWorkAreaTopWhenTheAnchorIsHigh() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 1050),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                verticalAnchor: .top,
                screens: ScreenFixtures.single
            )
            #expect(frame == PixelRect(x: 660, y: 745, width: 600, height: 300))
        }

        /// A low-y anchor drives the top-anchored origin negative; it clamps
        /// up to the padding inset.
        @Test func clampsToTheBottomPaddingWhenTheAnchorIsLow() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 960, y: 20),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                verticalAnchor: .top,
                screens: ScreenFixtures.single
            )
            #expect(frame == PixelRect(x: 660, y: 10, width: 600, height: 300))
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
                screens: ScreenFixtures.secondaryRight
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
                screens: ScreenFixtures.secondaryLeft
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
                screens: ScreenFixtures.stackedBelow
            )
            #expect(frame == PixelRect(x: 500, y: -890, width: 600, height: 300))
        }
    }

    @Suite struct OffScreenAnchorNearestScreen {
        /// An anchor on no screen (a window dragged mostly off-screen can
        /// have an off-screen center) falls back to the *nearest* screen —
        /// here the secondary, off whose top-right corner the anchor sits —
        /// and clamps the anchor-centered rect into its work area.
        @Test func fallsBackToTheNearestScreen() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 5000, y: 5000),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.secondaryRight
            )
            // Secondary work area (1920, 0, 1600, 875): the far-off anchor
            // clamps to the right/top corner of the padded area
            // (x 1920 + 1600 - 10 - 600 = 2910, y 875 - 10 - 300 = 565).
            #expect(frame == PixelRect(x: 2910, y: 565, width: 600, height: 300))
        }

        /// An off-screen anchor nearest the primary resolves onto the
        /// primary — never the secondary just because "nearest" happened to
        /// be evaluated first. Anchor (-5000, -5000) is nearest the primary
        /// at (0, 0, 1920, 1080), so it clamps to the primary's bottom-left.
        @Test func fallsBackToThePrimaryWhenItIsNearest() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: -5000, y: -5000),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.secondaryRight
            )
            #expect(frame == PixelRect(x: 10, y: 10, width: 600, height: 300))
        }
    }

    /// The multi-monitor boundary bug this fix targets: dragging a window to
    /// a secondary screen's very top edge used to open the panel on the
    /// primary, because no screen's half-open frame *contains* the exact top
    /// pixel (`y == frame.maxY`). Selecting the nearest screen keeps the
    /// panel on the secondary. The edge-trigger path is top-anchored, so the
    /// panel hangs below the cursor within the secondary's work area.
    @Suite struct SecondaryScreenOuterEdge {
        /// Secondary stacked above the primary: its top edge is
        /// y = 1080 + 900 = 1980. A cursor on that exact row must resolve to
        /// the secondary (work area (0, 1080, 1600, 875)), not the primary.
        @Test func resolvesTheSecondaryTopEdgeToTheSecondary() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 800, y: 1980),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                verticalAnchor: .top,
                screens: ScreenFixtures.stackedAbove
            )
            // Secondary work area (0, 1080, 1600, 875): padded y range
            // [1090, 1655]; the high anchor clamps the top-anchored origin to
            // 1080 + 875 - 10 - 300 = 1645. x centers at 800 - 300 = 500.
            #expect(frame == PixelRect(x: 500, y: 1645, width: 600, height: 300))
            // Squarely on the secondary, whose work area starts at y = 1080.
            #expect(frame!.y >= 1080)
        }

        /// Secondary to the right of the primary: its right edge is
        /// x = 1920 + 1600 = 3520. A cursor on that exact column must resolve
        /// to the secondary (work area (1920, 0, 1600, 875)), not the primary.
        @Test func resolvesTheSecondaryRightEdgeToTheSecondary() {
            let frame = PanelPositionResolver.resolve(
                anchor: PixelPoint(x: 3520, y: 400),
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                screens: ScreenFixtures.secondaryRight
            )
            // Secondary work area (1920, 0, 1600, 875): padded x range
            // [1930, 2910]; the right-edge anchor clamps x to 2910.
            #expect(frame == PixelRect(x: 2910, y: 250, width: 600, height: 300))
            // Squarely on the secondary, whose work area starts at x = 1920.
            #expect(frame!.x >= 1920)
        }
    }
}
