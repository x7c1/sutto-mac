import SuttoDomain
import Testing

@testable import SuttoOperations

/// Exercises ``EdgeTriggerUseCase`` end to end against fakes: a drag observer
/// the test pushes events through, a window controller whose frame the test
/// moves between reads, two fake schedulers fired on demand, a screen stub,
/// and a spy panel recording every call. No live monitor, AX, or clock is
/// involved.
@Suite @MainActor struct EdgeTriggerUseCaseTests {
    // MARK: - Fakes

    /// A `DragObserving` fake: captures the handler and lets the test emit
    /// drag events into it.
    private final class DragObserverFake: DragObserving {
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private var handler: (@MainActor (DragEvent) -> Void)?

        func start(onEvent: @escaping @MainActor (DragEvent) -> Void) {
            startCount += 1
            handler = onEvent
        }

        func stop() {
            stopCount += 1
            handler = nil
        }

        func emit(_ event: DragEvent) { handler?(event) }
    }

    private final class TargetWindowStub: TargetWindow {}

    /// A `WindowControlling` fake with a scriptable current frame that the
    /// test mutates between reads to simulate the window being dragged.
    private final class WindowControllerFake: WindowControlling {
        var captureSucceeds: Bool
        var currentFrame: PixelRect?
        private let target = TargetWindowStub()

        init(captureSucceeds: Bool = true, frame: PixelRect?) {
            self.captureSucceeds = captureSucceeds
            currentFrame = frame
        }

        func captureFocusedWindow() -> TargetWindow? {
            captureSucceeds ? target : nil
        }

        func frame(of window: TargetWindow) -> PixelRect? { currentFrame }

        func applyFrame(_ frame: PixelRect, to window: TargetWindow) -> Bool { true }
    }

    private final class ScreenProviderStub: ScreenProviding {
        var currentScreens: [Screen]

        init(screens: [Screen]) {
            currentScreens = screens
        }

        func screens() -> [Screen] { currentScreens }
    }

    /// A `Scheduling` fake: records the pending action and fires it on demand.
    private final class SchedulerFake: Scheduling {
        private var action: (@MainActor () -> Void)?
        private(set) var scheduleCount = 0
        private(set) var cancelCount = 0
        var isScheduled: Bool { action != nil }

        func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
            scheduleCount += 1
            self.action = action
        }

        func cancel() {
            cancelCount += 1
            action = nil
        }

        /// Fires the pending action, clearing it first (a one-shot timer).
        func fire() {
            let pending = action
            action = nil
            pending?()
        }
    }

    /// A spy `EdgeTriggerPanel` recording every call in order. `onHide` lets a
    /// test model the real panel's re-entrant dismissal: `LayoutPanel.hide()`
    /// fires `onDismiss`, which calls `notifyPanelDismissed()` synchronously.
    private final class PanelSpy: EdgeTriggerPanel {
        enum Call: Equatable {
            case show(PixelPoint)
            case move(PixelPoint)
            case hide
        }

        private(set) var calls: [Call] = []
        var onHide: (@MainActor () -> Void)?

        func show(at point: PixelPoint) { calls.append(.show(point)) }
        func move(to point: PixelPoint) { calls.append(.move(point)) }
        func hide() {
            calls.append(.hide)
            onHide?()
        }
    }

    // MARK: - Fixture

    /// A single 1000x1000 screen at the origin, so edge math is easy: a point
    /// with x <= 10 or >= 990 (etc.) counts as at an edge.
    private static let screen = Screen(
        frame: PixelRect(x: 0, y: 0, width: 1000, height: 1000),
        visibleFrame: PixelRect(x: 0, y: 0, width: 1000, height: 1000)
    )

    private static let windowOrigin = PixelRect(x: 200, y: 200, width: 400, height: 300)

    private struct Harness {
        let useCase: EdgeTriggerUseCase
        let drags: DragObserverFake
        let windows: WindowControllerFake
        let dwell: SchedulerFake
        let throttle: SchedulerFake
        let hide: SchedulerFake
        let panel: PanelSpy
    }

    private func makeHarness(
        captureSucceeds: Bool = true,
        windowFrame: PixelRect? = windowOrigin,
        screens: [Screen] = [screen]
    ) -> Harness {
        let drags = DragObserverFake()
        let windows = WindowControllerFake(captureSucceeds: captureSucceeds, frame: windowFrame)
        let dwell = SchedulerFake()
        let throttle = SchedulerFake()
        let hide = SchedulerFake()
        let panel = PanelSpy()
        let useCase = EdgeTriggerUseCase(
            drags: drags,
            windows: windows,
            screens: ScreenProviderStub(screens: screens),
            panel: panel,
            dwellTimer: dwell,
            throttle: throttle,
            hideTimer: hide
        )
        useCase.start()
        return Harness(
            useCase: useCase, drags: drags, windows: windows,
            dwell: dwell, throttle: throttle, hide: hide, panel: panel)
    }

    /// Moves the fake window's frame origin so the next `frame(of:)` read
    /// confirms a window move.
    private func moveWindow(_ windows: WindowControllerFake, by delta: Double) {
        let f = windows.currentFrame!
        windows.currentFrame = PixelRect(x: f.x + delta, y: f.y, width: f.width, height: f.height)
    }

    // MARK: - Lifecycle

    @Test func startSubscribesToTheDragObserver() {
        let h = makeHarness()
        #expect(h.drags.startCount == 1)
    }

    @Test func stopUnsubscribesAndCancelsTimers() {
        let h = makeHarness()
        h.useCase.stop()

        #expect(h.drags.stopCount == 1)
        #expect(h.dwell.cancelCount >= 1)
        #expect(h.throttle.cancelCount >= 1)
        #expect(h.hide.cancelCount >= 1)
    }

    // MARK: - Window-move discrimination

    @Test func ignoresADragWhoseWindowNeverMoves() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        // Window frame unchanged across moves → text-selection-like drag.
        h.drags.emit(.moved(PixelPoint(x: 5, y: 300)))  // at the left edge
        h.throttle.fire()
        h.drags.emit(.moved(PixelPoint(x: 5, y: 301)))
        h.throttle.fire()
        h.drags.emit(.ended)

        // The policy was never fed, so no dwell timer was armed and the panel
        // never appeared.
        #expect(h.dwell.scheduleCount == 0)
        #expect(h.panel.calls.isEmpty)
    }

    @Test func confirmsAWindowMoveThenFeedsThePolicy() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)  // window actually dragged
        // Move the pointer to the left edge (x <= 10).
        h.drags.emit(.moved(PixelPoint(x: 5, y: 300)))

        // Reaching the edge on a confirmed window move arms the dwell timer.
        #expect(h.dwell.scheduleCount == 1)
    }

    @Test func ignoresADragWhenNoWindowCouldBeCaptured() {
        let h = makeHarness(captureSucceeds: false)

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        h.drags.emit(.moved(PixelPoint(x: 5, y: 300)))
        h.throttle.fire()

        #expect(h.dwell.scheduleCount == 0)
        #expect(h.panel.calls.isEmpty)
    }

    @Test func ignoresADragWhenTheWindowFrameIsUnreadable() {
        let h = makeHarness(windowFrame: nil)

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        h.drags.emit(.moved(PixelPoint(x: 5, y: 300)))
        h.throttle.fire()

        #expect(h.dwell.scheduleCount == 0)
        #expect(h.panel.calls.isEmpty)
    }

    // MARK: - Throttle coalescing

    @Test func throttleCoalescesToTheLastPointDuringCooldown() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)

        // First move fires immediately (leading edge), away from any edge.
        h.drags.emit(.moved(PixelPoint(x: 500, y: 500)))
        #expect(h.throttle.scheduleCount == 1)

        // Moves during cooldown are coalesced; only the last should survive.
        h.drags.emit(.moved(PixelPoint(x: 600, y: 500)))
        h.drags.emit(.moved(PixelPoint(x: 5, y: 500)))  // final: at the left edge

        // Nothing new delivered yet (still cooling down): no dwell armed.
        #expect(h.dwell.scheduleCount == 0)

        // Trailing edge flush delivers the last coalesced point, which is at
        // the edge → arms the dwell.
        h.throttle.fire()
        #expect(h.dwell.scheduleCount == 1)
    }

    @Test func dragEndedFlushesThePendingCoalescedMove() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 500, y: 500)))  // leading edge, delivered
        h.drags.emit(.moved(PixelPoint(x: 5, y: 500)))  // coalesced, at edge

        #expect(h.dwell.scheduleCount == 0)

        // Ending the drag must not lose the final coalesced position: it is
        // delivered immediately, reaching the edge and arming the dwell.
        h.drags.emit(.ended)
        #expect(h.dwell.scheduleCount == 1)
    }

    // MARK: - Dwell → show → follow

    @Test func dwellElapsedShowsPanelAtCursor() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 5, y: 400)))  // at the left edge
        #expect(h.dwell.scheduleCount == 1)

        // Dwell fires → panel shows at the last pointer. No suppression: the
        // panel then dismisses on its own terms (auto-hide / click-outside).
        h.dwell.fire()
        #expect(h.panel.calls == [.show(PixelPoint(x: 5, y: 400))])
    }

    @Test func panelFollowsTheCursorWhileTriggeredAndDragging() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 5, y: 400)))  // edge → arm dwell
        h.dwell.fire()  // show panel

        // A further move that stays within the edge band follows the cursor.
        h.throttle.fire()  // clear the leading throttle window
        h.drags.emit(.moved(PixelPoint(x: 8, y: 450)))  // still at the left edge

        #expect(h.panel.calls.last == .move(PixelPoint(x: 8, y: 450)))
    }

    @Test func dragEndedStopsFollowButKeepsPanelShown() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 5, y: 400)))
        h.dwell.fire()  // panel shown
        h.throttle.fire()

        h.drags.emit(.ended)
        let callsAfterEnd = h.panel.calls.count

        // A new drag's moves no longer move the panel (follow stopped); the
        // panel is neither hidden nor re-shown by drag-ended itself.
        h.drags.emit(.began(PixelPoint(x: 400, y: 400)))
        // window does not move this time
        h.drags.emit(.moved(PixelPoint(x: 30, y: 460)))
        h.throttle.fire()
        #expect(h.panel.calls.count == callsAfterEnd)
    }

    // MARK: - Dismissal

    @Test func notifyPanelDismissedResetsAndCancelsTimer() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 5, y: 400)))
        h.dwell.fire()  // panel shown
        #expect(h.panel.calls == [.show(PixelPoint(x: 5, y: 400))])

        h.useCase.notifyPanelDismissed()

        // Dismissal drives no panel calls (no suppression API); it only
        // cancels the pending timer and returns the policy to idle.
        #expect(h.panel.calls == [.show(PixelPoint(x: 5, y: 400))])
        #expect(h.dwell.cancelCount >= 1)

        // Back to idle: a fresh confirmed window move must go through the full
        // arm cycle again rather than immediately moving a stale panel.
        let dwellBefore = h.dwell.scheduleCount
        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 5, y: 400)))
        #expect(h.dwell.scheduleCount == dwellBefore + 1)
    }

    // MARK: - Leave-edge grace before hiding

    /// Leaving the edge mid-drag no longer hides at once: it arms the grace
    /// timer and keeps the panel. Firing the grace hides the panel.
    @Test func leavingTheEdgeMidDragArmsTheGraceThenHidesOnFire() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 5, y: 400)))  // left edge → arm dwell
        h.dwell.fire()  // show
        #expect(h.panel.calls == [.show(PixelPoint(x: 5, y: 400))])

        // Clear the leading throttle window, then pull the pointer off the
        // edge: the grace timer arms but the panel stays up.
        h.throttle.fire()
        h.drags.emit(.moved(PixelPoint(x: 500, y: 500)))  // well off any edge
        #expect(h.hide.scheduleCount == 1)
        #expect(h.panel.calls == [.show(PixelPoint(x: 5, y: 400))])  // not hidden yet

        // The grace elapses with the pointer still off the edge: now hide.
        h.hide.fire()
        #expect(h.panel.calls.last == .hide)
    }

    /// Re-entering the edge before the grace elapses cancels the pending hide
    /// and keeps the panel — the panel is never hidden.
    @Test func reEnteringTheEdgeWithinTheGraceCancelsTheHide() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 5, y: 400)))
        h.dwell.fire()  // show
        h.throttle.fire()
        h.drags.emit(.moved(PixelPoint(x: 500, y: 500)))  // off edge → arm grace
        #expect(h.hide.scheduleCount == 1)
        #expect(h.hide.isScheduled)

        // Return to the edge within the grace: the pending hide is cancelled
        // and the panel was never hidden.
        h.throttle.fire()
        h.drags.emit(.moved(PixelPoint(x: 8, y: 420)))  // back at the left edge
        #expect(h.hide.cancelCount >= 1)
        #expect(!h.hide.isScheduled)
        #expect(!h.panel.calls.contains(.hide))
    }

    @Test func afterTheGraceHidesReApproachReTriggersWithinTheSameDrag() {
        let h = makeHarness()

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 5, y: 400)))
        h.dwell.fire()  // show
        h.throttle.fire()
        h.drags.emit(.moved(PixelPoint(x: 500, y: 500)))  // off edge → arm grace
        h.hide.fire()  // grace elapsed → hide
        #expect(h.panel.calls.last == .hide)

        // Re-approach the edge within the same drag: the dwell re-arms and
        // firing it re-shows the panel — no new drag-began needed.
        let dwellBefore = h.dwell.scheduleCount
        h.throttle.fire()
        h.drags.emit(.moved(PixelPoint(x: 8, y: 420)))  // back at the left edge
        #expect(h.dwell.scheduleCount == dwellBefore + 1)
        h.dwell.fire()
        #expect(h.panel.calls.last == .show(PixelPoint(x: 8, y: 420)))
    }

    /// The real panel's `hide()` fires `onDismiss`, which calls
    /// `notifyPanelDismissed()` synchronously. When the grace elapses and
    /// hides the panel, that re-entrant path must not corrupt state or loop,
    /// and — because the drag is still live — must leave the per-drag tracking
    /// intact so a re-approach re-shows.
    @Test func reEntrantHideOnGraceElapseKeepsTheDragLiveWithoutLooping() {
        let h = makeHarness()
        h.panel.onHide = { [weak useCase = h.useCase] in
            useCase?.notifyPanelDismissed()
        }

        h.drags.emit(.began(PixelPoint(x: 300, y: 300)))
        moveWindow(h.windows, by: 50)
        h.drags.emit(.moved(PixelPoint(x: 5, y: 400)))
        h.dwell.fire()  // show
        h.throttle.fire()

        // Leave the edge → arm grace; firing it hides → hide() → onDismiss →
        // notifyPanelDismissed re-entrant (policy already in `dragging`).
        h.drags.emit(.moved(PixelPoint(x: 500, y: 500)))
        h.hide.fire()
        #expect(h.panel.calls == [.show(PixelPoint(x: 5, y: 400)), .hide])

        // Drag still live: re-approach re-arms and re-shows without a fresh
        // drag-began, proving the re-entrant dismissal left tracking intact.
        h.throttle.fire()
        h.drags.emit(.moved(PixelPoint(x: 8, y: 420)))
        h.dwell.fire()
        #expect(h.panel.calls.last == .show(PixelPoint(x: 8, y: 420)))
    }
}
