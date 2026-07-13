import SuttoDomain
import Testing

@testable import SuttoOperations

/// A `WindowControlling` stub with a scriptable focused-window frame.
@MainActor
private final class WindowControllerStub: WindowControlling {
    var focusedFrame: PixelRect?

    init(focusedFrame: PixelRect?) {
        self.focusedFrame = focusedFrame
    }

    func focusedWindowFrame() -> PixelRect? { focusedFrame }
    func applyFrame(_ frame: PixelRect) -> Bool { true }
}

/// A `ScreenProviding` stub with a scriptable arrangement and mouse.
@MainActor
private final class ScreenProviderStub: ScreenProviding {
    var currentScreens: [Screen]
    var mouse: PixelPoint

    init(screens: [Screen], mouse: PixelPoint = PixelPoint(x: 100, y: 100)) {
        currentScreens = screens
        self.mouse = mouse
    }

    func screens() -> [Screen] { currentScreens }
    func mouseLocation() -> PixelPoint { mouse }
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
            windows: WindowControllerStub(
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
            windows: WindowControllerStub(
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
            windows: WindowControllerStub(focusedFrame: nil),
            screens: ScreenProviderStub(screens: [primary])
        )
        #expect(useCase.panelFrame(width: 400, height: 200) == nil)
    }

    @Test func returnsNilWithoutScreens() {
        let useCase = PanelPositionUseCase(
            windows: WindowControllerStub(
                focusedFrame: PixelRect(x: 200, y: 200, width: 800, height: 600)),
            screens: ScreenProviderStub(screens: [])
        )
        #expect(useCase.panelFrame(width: 400, height: 200) == nil)
    }
}
