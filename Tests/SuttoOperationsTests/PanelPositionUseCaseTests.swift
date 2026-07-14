import SuttoDomain
import Testing

@testable import SuttoOperations

/// A `TargetWindow` stub the fake controller hands back on capture.
private final class TargetWindowStub: TargetWindow {}

/// A `WindowControlling` stub whose capture yields a stub target with a
/// scriptable frame (or no target at all).
@MainActor
private final class WindowControllerStub: WindowControlling {
    var focusedFrame: PixelRect?
    private let target = TargetWindowStub()

    init(focusedFrame: PixelRect?) {
        self.focusedFrame = focusedFrame
    }

    func captureFocusedWindow() -> TargetWindow? {
        focusedFrame == nil ? nil : target
    }
    func frame(of window: TargetWindow) -> PixelRect? { focusedFrame }
    func applyFrame(_ frame: PixelRect, to window: TargetWindow) -> Bool { true }
}

/// Builds a session over a stub whose captured window has `focusedFrame`,
/// capturing up front the way the panel does before it is shown.
@MainActor
private func makeSession(focusedFrame: PixelRect?) -> PanelTargetSession {
    let session = PanelTargetSession(windows: WindowControllerStub(focusedFrame: focusedFrame))
    session.capture()
    return session
}

/// A `ScreenProviding` stub with a scriptable arrangement.
@MainActor
private final class ScreenProviderStub: ScreenProviding {
    var currentScreens: [Screen]

    init(screens: [Screen]) {
        currentScreens = screens
    }

    func screens() -> [Screen] { currentScreens }
}

/// The fixture: a primary 1920x1080 screen whose work area is 1920x1055
/// (25 px menu bar at the top).
private let primary = Screen(
    frame: PixelRect(x: 0, y: 0, width: 1920, height: 1080),
    visibleFrame: PixelRect(x: 0, y: 0, width: 1920, height: 1055)
)

@MainActor
@Suite struct PanelPositionUseCaseTests {
    /// The window frame arrives in AX coordinates (top-left origin) and
    /// must be converted before its center anchors the panel: an AX frame
    /// (200, 200, 800, 600) is AppKit (200, 280, 800, 600), so the anchor
    /// is (600, 580) and a 400x200 panel centers at (400, 480).
    @Test func centersThePanelOverTheFocusedWindow() {
        let useCase = PanelPositionUseCase(
            session: makeSession(
                focusedFrame: PixelRect(x: 200, y: 200, width: 800, height: 600)),
            screens: ScreenProviderStub(screens: [primary])
        )
        let frame = useCase.panelFrame(width: 400, height: 200)
        #expect(frame == PixelRect(x: 400, y: 480, width: 400, height: 200))
    }

    /// A window against the AX top-left corner (over the menu bar edge)
    /// produces a clamped panel: the resolver's 10 px padding inside the
    /// work area, not the raw centered position.
    @Test func clampsWhenTheWindowSitsAtTheScreenEdge() {
        let useCase = PanelPositionUseCase(
            session: makeSession(
                focusedFrame: PixelRect(x: 0, y: 25, width: 300, height: 200)),
            screens: ScreenProviderStub(screens: [primary])
        )
        // AX (0, 25, 300, 200) → AppKit (0, 855, 300, 200), center
        // (150, 955). Centered 400x200 rect (−50, 855) clamps to x = 10
        // and to the top-of-work-area origin 1055 − 10 − 200 = 845.
        let frame = useCase.panelFrame(width: 400, height: 200)
        #expect(frame == PixelRect(x: 10, y: 845, width: 400, height: 200))
    }

    /// No focused window (or no Accessibility permission — the AX read
    /// returns nil either way): the caller falls back to mouse-screen
    /// centering, so the use case reports nil rather than guessing.
    @Test func returnsNilWithoutAFocusedWindow() {
        let useCase = PanelPositionUseCase(
            session: makeSession(focusedFrame: nil),
            screens: ScreenProviderStub(screens: [primary])
        )
        #expect(useCase.panelFrame(width: 400, height: 200) == nil)
    }

    @Test func returnsNilWithoutScreens() {
        let useCase = PanelPositionUseCase(
            session: makeSession(
                focusedFrame: PixelRect(x: 200, y: 200, width: 800, height: 600)),
            screens: ScreenProviderStub(screens: [])
        )
        #expect(useCase.panelFrame(width: 400, height: 200) == nil)
    }

    /// The anchored (edge-trigger) path hangs the panel below the cursor —
    /// centered on the cursor's x, its top edge at the cursor's y — when the
    /// cursor sits comfortably inside the work area. No captured window
    /// needed, so it resolves even with none. Anchor (960, 540) with a
    /// 400x200 panel: x = 960 − 200 = 760, and the top edge sits at 540 so
    /// the origin is 540 − 200 = 340.
    @Test func anchorsTheEdgeTriggerPanelTopEdgeAtTheCursor() {
        let useCase = PanelPositionUseCase(
            session: makeSession(focusedFrame: nil),
            screens: ScreenProviderStub(screens: [primary])
        )
        let frame = useCase.panelFrame(
            width: 400, height: 200, anchoredAt: PixelPoint(x: 960, y: 540))
        #expect(frame == PixelRect(x: 760, y: 340, width: 400, height: 200))
        // The top edge (origin.y + height) lands exactly on the cursor.
        #expect(frame!.y + frame!.height == 540)
    }

    /// A cursor near the top of the work area: hanging the panel below would
    /// run it off the bottom padding, so the top-edge clamp wins and the
    /// panel's top edge is pushed down to the padding inset. Anchor
    /// (960, 1050): raw top-anchored origin 1050 − 200 = 850 clamps to the
    /// work-area top origin 1055 − 10 − 200 = 845; x stays centered at 760.
    @Test func clampsTheEdgeTriggerPanelAtTheTopEdge() {
        let useCase = PanelPositionUseCase(
            session: makeSession(focusedFrame: nil),
            screens: ScreenProviderStub(screens: [primary])
        )
        let frame = useCase.panelFrame(
            width: 400, height: 200, anchoredAt: PixelPoint(x: 960, y: 1050))
        #expect(frame == PixelRect(x: 760, y: 845, width: 400, height: 200))
    }

    /// A cursor near the bottom edge: the top-anchored origin goes negative
    /// and clamps to the padding inset. Anchor (960, 5): raw origin
    /// 5 − 200 = −195 clamps to y = 10; x stays centered at 760.
    @Test func clampsTheEdgeTriggerPanelAtTheBottomEdge() {
        let useCase = PanelPositionUseCase(
            session: makeSession(focusedFrame: nil),
            screens: ScreenProviderStub(screens: [primary])
        )
        let frame = useCase.panelFrame(
            width: 400, height: 200, anchoredAt: PixelPoint(x: 960, y: 5))
        #expect(frame == PixelRect(x: 760, y: 10, width: 400, height: 200))
    }

    /// A cursor near the left edge clamps horizontally to the padding while
    /// keeping the top edge at the cursor, landing the cursor at the panel's
    /// top-left corner. Anchor (5, 540): x = 5 − 200 = −195 clamps to 10;
    /// y = 540 − 200 = 340 (unclamped).
    @Test func clampsTheEdgeTriggerPanelAtTheLeftEdge() {
        let useCase = PanelPositionUseCase(
            session: makeSession(focusedFrame: nil),
            screens: ScreenProviderStub(screens: [primary])
        )
        let frame = useCase.panelFrame(
            width: 400, height: 200, anchoredAt: PixelPoint(x: 5, y: 540))
        #expect(frame == PixelRect(x: 10, y: 340, width: 400, height: 200))
    }

    /// A cursor near the right edge clamps horizontally to the right-edge
    /// origin, landing the cursor at the panel's top-right corner. Anchor
    /// (1915, 540): x = 1915 − 200 = 1715 clamps to 1920 − 10 − 400 = 1510;
    /// y = 340 (unclamped).
    @Test func clampsTheEdgeTriggerPanelAtTheRightEdge() {
        let useCase = PanelPositionUseCase(
            session: makeSession(focusedFrame: nil),
            screens: ScreenProviderStub(screens: [primary])
        )
        let frame = useCase.panelFrame(
            width: 400, height: 200, anchoredAt: PixelPoint(x: 1915, y: 540))
        #expect(frame == PixelRect(x: 1510, y: 340, width: 400, height: 200))
    }

    @Test func anchoredPathReturnsNilWithoutScreens() {
        let useCase = PanelPositionUseCase(
            session: makeSession(focusedFrame: nil),
            screens: ScreenProviderStub(screens: [])
        )
        #expect(
            useCase.panelFrame(
                width: 400, height: 200, anchoredAt: PixelPoint(x: 960, y: 540)) == nil)
    }
}
