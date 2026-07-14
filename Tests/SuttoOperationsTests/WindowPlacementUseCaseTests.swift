import SuttoDomain
import Testing

@testable import SuttoOperations

/// A `PermissionChecking` stub with a scriptable status.
@MainActor
private final class PermissionCheckerStub: PermissionChecking {
    var status: AccessibilityAuthorization

    init(status: AccessibilityAuthorization) {
        self.status = status
    }

    func currentStatus() -> AccessibilityAuthorization { status }
    func requestPermission() {}
}

/// A `TargetWindow` stub, identifiable by reference so tests can assert
/// that positioning and placement operated on the *same* captured window.
private final class TargetWindowStub: TargetWindow {}

/// A `WindowControlling` stub whose capture yields a single stub target
/// with a scriptable frame; it records every frame applied and the target
/// each `frame(of:)` / `applyFrame(_:to:)` call was handed.
@MainActor
private final class WindowControllerStub: WindowControlling {
    var focusedFrame: PixelRect?
    var applySucceeds = true
    let target = TargetWindowStub()
    private(set) var appliedFrames: [PixelRect] = []
    private(set) var queriedTargets: [ObjectIdentifier] = []
    private(set) var appliedTargets: [ObjectIdentifier] = []

    init(focusedFrame: PixelRect?) {
        self.focusedFrame = focusedFrame
    }

    func captureFocusedWindow() -> TargetWindow? {
        focusedFrame == nil ? nil : target
    }

    func frame(of window: TargetWindow) -> PixelRect? {
        queriedTargets.append(ObjectIdentifier(window))
        return focusedFrame
    }

    func applyFrame(_ frame: PixelRect, to window: TargetWindow) -> Bool {
        appliedFrames.append(frame)
        appliedTargets.append(ObjectIdentifier(window))
        return applySucceeds
    }
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

private let leftHalf = Layout(
    label: "Left Half",
    position: LayoutPosition(x: "0", y: "0"),
    size: LayoutSize(width: "50%", height: "100%")
)

/// The fixture arrangement: primary 1920x1080 with work area (0, 0, 1920,
/// 1055), secondary 1600x900 to the right with work area (1920, 0, 1600,
/// 875). Expected AX frames are hand-computed the same way as in the
/// domain-level `PlacementFrameResolverTests`.
private func makeScreens() -> [Screen] {
    [
        Screen(
            frame: PixelRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: PixelRect(x: 0, y: 0, width: 1920, height: 1055)
        ),
        Screen(
            frame: PixelRect(x: 1920, y: 0, width: 1600, height: 900),
            visibleFrame: PixelRect(x: 1920, y: 0, width: 1600, height: 875)
        ),
    ]
}

// AX (200, 200, 800, 600): AppKit y = 1080 - 800 = 280, center (600, 580) —
// on the primary screen.
private let windowOnPrimary = PixelRect(x: 200, y: 200, width: 800, height: 600)

@Suite @MainActor struct WindowPlacementUseCaseTests {
    private func makeUseCase(
        permission: AccessibilityAuthorization = .granted,
        windowFrame: PixelRect? = windowOnPrimary,
        screens: [Screen] = makeScreens(),
        mouse: PixelPoint = PixelPoint(x: 100, y: 100)
    ) -> (WindowPlacementUseCase, WindowControllerStub) {
        let (useCase, windows, _) = makeUseCaseAndSession(
            permission: permission, windowFrame: windowFrame, screens: screens, mouse: mouse)
        return (useCase, windows)
    }

    /// Builds the placement use case over a freshly captured session — the
    /// state the panel is in right after `show()` captures its target.
    private func makeUseCaseAndSession(
        permission: AccessibilityAuthorization = .granted,
        windowFrame: PixelRect? = windowOnPrimary,
        screens: [Screen] = makeScreens(),
        mouse: PixelPoint = PixelPoint(x: 100, y: 100)
    ) -> (WindowPlacementUseCase, WindowControllerStub, PanelTargetSession) {
        let windows = WindowControllerStub(focusedFrame: windowFrame)
        let session = PanelTargetSession(windows: windows)
        session.capture()
        let useCase = WindowPlacementUseCase(
            permission: PermissionCheckerStub(status: permission),
            session: session,
            screens: ScreenProviderStub(screens: screens, mouse: mouse)
        )
        return (useCase, windows, session)
    }

    @Test func appliesTheResolvedFrameForTheWindowScreen() {
        let (useCase, windows) = makeUseCase()

        useCase.place(leftHalf)

        // Left half of the primary's AX work area (0, 25, 1920, 1055).
        #expect(windows.appliedFrames == [PixelRect(x: 0, y: 25, width: 960, height: 1055)])
    }

    @Test func targetsTheScreenContainingTheWindowCenter() {
        // Window on the secondary: AX (2000, 300, 800, 600) → AppKit center
        // (2400, 480). The mouse stays on the primary to prove the window's
        // screen wins.
        let (useCase, windows) = makeUseCase(
            windowFrame: PixelRect(x: 2000, y: 300, width: 800, height: 600)
        )

        useCase.place(leftHalf)

        // Left half of the secondary's AX work area (1920, 205, 1600, 875).
        #expect(windows.appliedFrames == [PixelRect(x: 1920, y: 205, width: 800, height: 875)])
    }

    @Test func fallsBackToTheMouseScreenForAnOffScreenWindowCenter() {
        // AX (10000, 10000, 100, 100) has its center on no screen; the
        // mouse at AppKit (2400, 480) is on the secondary.
        let (useCase, windows) = makeUseCase(
            windowFrame: PixelRect(x: 10000, y: 10000, width: 100, height: 100),
            mouse: PixelPoint(x: 2400, y: 480)
        )

        useCase.place(leftHalf)

        #expect(windows.appliedFrames == [PixelRect(x: 1920, y: 205, width: 800, height: 875)])
    }

    @Test func fallsBackToThePrimaryWhenWindowAndMouseAreOffScreen() {
        let (useCase, windows) = makeUseCase(
            windowFrame: PixelRect(x: 10000, y: 10000, width: 100, height: 100),
            mouse: PixelPoint(x: 99999, y: 99999)
        )

        useCase.place(leftHalf)

        #expect(windows.appliedFrames == [PixelRect(x: 0, y: 25, width: 960, height: 1055)])
    }

    @Test func skipsPlacementWithoutTheAccessibilityPermission() {
        let (useCase, windows) = makeUseCase(permission: .denied)

        useCase.place(leftHalf)

        #expect(windows.appliedFrames.isEmpty)
    }

    @Test func skipsPlacementWithoutAFocusedWindow() {
        let (useCase, windows) = makeUseCase(windowFrame: nil)

        useCase.place(leftHalf)

        #expect(windows.appliedFrames.isEmpty)
    }

    @Test func skipsPlacementWithoutScreens() {
        let (useCase, windows) = makeUseCase(screens: [])

        useCase.place(leftHalf)

        #expect(windows.appliedFrames.isEmpty)
    }

    @Test func skipsPlacementForAnInvalidLayoutExpression() {
        let broken = Layout(
            label: "broken",
            position: LayoutPosition(x: "abc", y: "0"),
            size: LayoutSize(width: "50%", height: "100%")
        )
        let (useCase, windows) = makeUseCase()

        useCase.place(broken)

        #expect(windows.appliedFrames.isEmpty)
    }

    // MARK: - Explicit display key (cross-monitor placement)

    @Test func placesOnTheScreenNamedByTheDisplayKey() {
        // The window sits on the primary; the clicked miniature names the
        // secondary — the window must land there regardless.
        let (useCase, windows) = makeUseCase()

        useCase.place(leftHalf, onDisplayKey: "1")

        // Left half of the secondary's AX work area (1920, 205, 1600, 875).
        #expect(windows.appliedFrames == [PixelRect(x: 1920, y: 205, width: 800, height: 875)])
    }

    @Test func displayKeyZeroTargetsThePrimaryFromAnywhere() {
        // The window sits on the secondary; key "0" pulls it to the primary.
        let (useCase, windows) = makeUseCase(
            windowFrame: PixelRect(x: 2000, y: 300, width: 800, height: 600)
        )

        useCase.place(leftHalf, onDisplayKey: "0")

        #expect(windows.appliedFrames == [PixelRect(x: 0, y: 25, width: 960, height: 1055)])
    }

    /// A collection made for more displays than are attached: the GNOME
    /// applicator skips placement when the monitor key resolves to nothing,
    /// and so does this path.
    @Test func skipsPlacementWhenTheDisplayKeyExceedsConnectedScreens() {
        let (useCase, windows) = makeUseCase()

        useCase.place(leftHalf, onDisplayKey: "2")

        #expect(windows.appliedFrames.isEmpty)
    }

    @Test func skipsPlacementForAMalformedDisplayKey() {
        let (useCase, windows) = makeUseCase()

        useCase.place(leftHalf, onDisplayKey: "not-a-number")

        #expect(windows.appliedFrames.isEmpty)
    }

    @Test func displayKeyPlacementSharesTheCommonGuards() {
        let (denied, deniedWindows) = makeUseCase(permission: .denied)
        denied.place(leftHalf, onDisplayKey: "0")
        #expect(deniedWindows.appliedFrames.isEmpty)

        let (noWindow, noWindowWindows) = makeUseCase(windowFrame: nil)
        noWindow.place(leftHalf, onDisplayKey: "0")
        #expect(noWindowWindows.appliedFrames.isEmpty)

        let (noScreens, noScreensWindows) = makeUseCase(screens: [])
        noScreens.place(leftHalf, onDisplayKey: "0")
        #expect(noScreensWindows.appliedFrames.isEmpty)
    }

    @Test func survivesAnApplyFailure() {
        let (useCase, windows) = makeUseCase()
        windows.applySucceeds = false

        useCase.place(leftHalf)
        useCase.place(leftHalf)

        // Failure is logged, not fatal: the next attempt still goes through.
        #expect(windows.appliedFrames.count == 2)
    }

    // MARK: - One captured target for positioning and placement

    /// The core invariant: the window the panel positions itself over and
    /// the window a selected layout is applied to are one and the same —
    /// the single window captured when the panel opened. Positioning and
    /// placement share one session, so both must reach the same target.
    @Test func positioningAndPlacementActOnTheSameCapturedTarget() {
        let (placement, windows, session) = makeUseCaseAndSession()
        let positioning = PanelPositionUseCase(
            session: session,
            screens: ScreenProviderStub(screens: makeScreens())
        )

        _ = positioning.panelFrame(width: 400, height: 200)
        placement.place(leftHalf)

        // The frame read for positioning and the frame written for
        // placement both went to the one captured stub target.
        #expect(windows.queriedTargets.allSatisfy { $0 == ObjectIdentifier(windows.target) })
        #expect(windows.appliedTargets == [ObjectIdentifier(windows.target)])
        #expect(!windows.queriedTargets.isEmpty)
    }

    /// When capture yields nothing (no focused window, or the permission is
    /// missing) placement is skipped — nothing is applied, exactly as when
    /// the old lazy resolution returned no window.
    @Test func skipsPlacementWhenNothingWasCaptured() {
        let (useCase, windows) = makeUseCase(windowFrame: nil)

        useCase.place(leftHalf)
        useCase.place(leftHalf, onDisplayKey: "0")

        #expect(windows.appliedFrames.isEmpty)
    }
}
