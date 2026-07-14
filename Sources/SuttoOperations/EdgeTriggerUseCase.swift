import SuttoDomain
import os

/// Orchestrates the edge-drag trigger: it watches the global left-drag
/// stream, decides which drags are genuine window moves, runs the pure
/// ``SuttoDomain/EdgeTriggerPolicy`` with a real dwell timer, and drives the
/// layout panel from the policy's effects.
///
/// This is the macOS analogue of the GNOME version's `DragCoordinator`
/// *plumbing* — the part the pure policy deliberately left out. Everything it
/// touches is behind a protocol (``DragObserving``, ``WindowControlling``,
/// ``ScreenProviding``, ``Scheduling``, ``EdgeTriggerPanel``), so the whole
/// interaction is unit-testable against stubs with no live monitor, AX, or
/// clock.
///
/// **Window-move discrimination.** ``DragObserving`` cannot tell a window
/// move from text selection or an in-app drag. So on drag-began the use case
/// captures the frontmost focused window and remembers its frame origin, then
/// on each (throttled) move re-reads that origin: only once the window has
/// actually shifted by more than ``windowMoveTolerance`` does it treat the
/// drag as a window move and start feeding the policy. A drag whose window
/// never moves (or whose window cannot be read) is ignored entirely — the
/// panel never appears for a text-selection drag.
///
/// **Throttle.** macOS delivers drag events very frequently. Processing every
/// one would mean an AX frame read per event; instead moves are coalesced to
/// a ~50 ms cadence (``throttleInterval``, GNOME's `MONITOR_INTERVAL`
/// reinterpreted). The throttle is leading + trailing: the first move in a
/// window fires immediately and the last move in the window is never dropped,
/// so the panel-follow rests exactly on the final cursor position rather than
/// a frame behind.
///
/// **Dismissal.** The edge-triggered panel dismisses exactly like the
/// shortcut-triggered one: it auto-hides once the cursor has left it, and a
/// click outside it closes it. No suppression is needed. During the drag the
/// cursor follows the panel, so auto-hide does not fire; the click-outside
/// monitor watches mouse-*down*, which does not occur mid-drag (the button is
/// already held — the drop is a mouse-*up*). After the drop, moving the cursor
/// off the panel lets it auto-hide, and clicking elsewhere dismisses it.
/// ``notifyPanelDismissed()`` is the hook the composition layer calls whenever
/// the panel closes (auto-hide, click-outside, Escape, or layout selection),
/// returning the policy to idle.
///
/// Not this type's concern: whether the feature is enabled (a preference), or
/// coexistence with macOS tiling. The composition layer calls ``start()``
/// only when the feature is on.
@MainActor
public final class EdgeTriggerUseCase {
    /// How far (in pixels) the captured window's frame origin must move from
    /// where it sat at drag-began before the drag counts as a genuine window
    /// move. A few pixels of slack absorbs the sub-pixel jitter AX reports
    /// for a window that has not actually been dragged, without swallowing a
    /// real move.
    public static let windowMoveTolerance: Double = 3

    /// The dwell the pointer must hold at an edge before the panel opens —
    /// GNOME's `EDGE_DELAY`. The pure policy is clock-free, so this duration
    /// lives here with the timer that enforces it.
    public static let dwellInterval: Duration = .milliseconds(200)

    /// The minimum spacing between processed drag moves — GNOME's
    /// `MONITOR_INTERVAL`, reinterpreted from a poll interval into a throttle
    /// window because macOS pushes drag events rather than being polled.
    public static let throttleInterval: Duration = .milliseconds(50)

    private let drags: any DragObserving
    private let windows: any WindowControlling
    private let screens: any ScreenProviding
    private let panel: any EdgeTriggerPanel
    private let dwellTimer: any Scheduling
    private let throttle: any Scheduling
    private var policy: EdgeTriggerPolicy
    private let logger = Logger(
        subsystem: "io.github.x7c1.SuttoMac", category: "edge-trigger")

    // MARK: Per-drag window-move tracking

    /// The window captured at drag-began, whose frame we watch to decide
    /// whether this drag is a real move. `nil` between drags or when nothing
    /// could be captured (the drag is then ignored).
    private var capturedWindow: (any TargetWindow)?
    /// The captured window's frame origin at drag-began (AX coordinates), the
    /// baseline the move test compares against.
    private var initialOrigin: PixelPoint?
    /// Whether this drag has been confirmed a genuine window move; once true
    /// it stays true for the rest of the drag.
    private var windowMoveConfirmed = false
    /// Whether ``SuttoDomain/EdgeTriggerPolicy/Event/dragBegan`` has been fed
    /// for this drag — sent once, the moment the move is first confirmed.
    private var forwardedDragBegan = false

    // MARK: Throttle state

    /// The most recent drag point observed during a throttle cooldown, not
    /// yet processed. Delivered on the trailing edge so the final position is
    /// never lost.
    private var throttlePending: PixelPoint?
    /// Whether a throttle window is currently open (a flush is scheduled).
    private var throttleCoolingDown = false

    public init(
        drags: any DragObserving,
        windows: any WindowControlling,
        screens: any ScreenProviding,
        panel: any EdgeTriggerPanel,
        dwellTimer: any Scheduling,
        throttle: any Scheduling,
        policy: EdgeTriggerPolicy = EdgeTriggerPolicy()
    ) {
        self.drags = drags
        self.windows = windows
        self.screens = screens
        self.panel = panel
        self.dwellTimer = dwellTimer
        self.throttle = throttle
        self.policy = policy
    }

    // MARK: - Lifecycle

    /// Starts observing drags. Enable/preference gating is the composition
    /// layer's job: it calls this only when the feature is on.
    public func start() {
        drags.start { [weak self] event in
            self?.handle(event)
        }
    }

    /// Stops observing and tears down any pending timers and drag state.
    public func stop() {
        drags.stop()
        dwellTimer.cancel()
        throttle.cancel()
        resetThrottle()
        resetDragTracking()
    }

    /// Called by the composition layer when the panel is dismissed — a layout
    /// was selected, or it auto-hid, or a click outside or Escape closed it.
    /// Returns the policy to ``SuttoDomain/EdgeTriggerPolicy/State/idle`` and
    /// cancels any pending dwell timer and drag tracking.
    ///
    /// This is also re-entered synchronously from the `hidePanel` effect
    /// (`panel.hide()` fires `onDismiss`, which calls this). In that case the
    /// drag is still live and the policy is already in `dragging`, so
    /// `panelDismissed` is a no-op and the state does not return to idle: the
    /// per-drag teardown below is skipped so the drag survives and a
    /// re-approach can re-arm. The teardown runs only when the dismissal
    /// actually ended the interaction (policy back to idle).
    public func notifyPanelDismissed() {
        apply(policy.handle(.panelDismissed))
        guard policy.state == .idle else { return }
        dwellTimer.cancel()
        throttle.cancel()
        resetThrottle()
        resetDragTracking()
    }

    // MARK: - Drag stream

    private func handle(_ event: DragEvent) {
        switch event {
        case .began:
            onDragBegan()
        case let .moved(point):
            onDragMoved(point)
        case .ended:
            onDragEnded()
        }
    }

    private func onDragBegan() {
        resetThrottle()
        resetDragTracking()

        guard let window = windows.captureFocusedWindow() else {
            // No frontmost focused window (or AX permission missing): this
            // drag cannot be a window move, so ignore it. Best-effort, not
            // fatal — matches WindowPlacementUseCase's logging style.
            logger.debug("drag ignored: no focused window to correlate the move with")
            return
        }
        guard let frame = windows.frame(of: window) else {
            logger.debug("drag ignored: captured window frame unreadable")
            return
        }
        capturedWindow = window
        initialOrigin = PixelPoint(x: frame.x, y: frame.y)
    }

    private func onDragMoved(_ point: PixelPoint) {
        // Leading + trailing throttle. The first move fires immediately; moves
        // during the cooldown are coalesced into `throttlePending` and the
        // last one is flushed on the trailing edge, so nothing is dropped.
        guard !throttleCoolingDown else {
            throttlePending = point
            return
        }
        deliverMove(point)
        throttlePending = nil
        throttleCoolingDown = true
        throttle.schedule(after: Self.throttleInterval) { [weak self] in
            self?.onThrottleFlush()
        }
    }

    private func onThrottleFlush() {
        throttleCoolingDown = false
        guard let pending = throttlePending else { return }
        throttlePending = nil
        // Re-enter the leading branch: deliver the coalesced point and open a
        // fresh window in case more moves are still arriving.
        onDragMoved(pending)
    }

    private func onDragEnded() {
        // Deliver any coalesced move immediately so the panel rests on the
        // final cursor position instead of a throttle window behind it.
        throttle.cancel()
        if let pending = throttlePending {
            deliverMove(pending)
        }
        resetThrottle()

        apply(policy.handle(.dragEnded))
        resetDragTracking()
    }

    /// Runs the window-move discrimination for one (throttled) drag point and,
    /// once the move is confirmed, feeds the policy.
    private func deliverMove(_ point: PixelPoint) {
        guard let window = capturedWindow, let initialOrigin else {
            // The drag was never a candidate (nothing captured at began).
            return
        }
        guard let frame = windows.frame(of: window) else {
            // Transient AX read failure: skip this sample, keep watching.
            logger.debug("drag move skipped: window frame temporarily unreadable")
            return
        }

        if !windowMoveConfirmed {
            let movedX = abs(frame.x - initialOrigin.x)
            let movedY = abs(frame.y - initialOrigin.y)
            guard movedX > Self.windowMoveTolerance || movedY > Self.windowMoveTolerance
            else {
                // Window has not moved yet: not a window drag (yet). Ignore.
                return
            }
            windowMoveConfirmed = true
        }

        if !forwardedDragBegan {
            forwardedDragBegan = true
            apply(policy.handle(.dragBegan))
        }
        guard let screenFrame = screenFrame(containing: point) else {
            logger.debug("drag move skipped: no screen to resolve the pointer against")
            return
        }
        apply(policy.handle(.pointerMoved(point, screenFrame: screenFrame)))
    }

    // MARK: - Effect application

    private func apply(_ effect: EdgeTriggerPolicy.Effect) {
        switch effect {
        case .none:
            break
        case .armDwellTimer:
            dwellTimer.schedule(after: Self.dwellInterval) { [weak self] in
                self?.onDwellElapsed()
            }
        case .cancelDwellTimer:
            dwellTimer.cancel()
        case let .showPanel(point):
            // The panel then dismisses on its own terms (auto-hide once the
            // cursor leaves it, or a click outside) — no suppression needed.
            panel.show(at: point)
        case let .movePanel(point):
            panel.move(to: point)
        case .hidePanel:
            // The drag left the edge band: hide the panel. `hide()` fires the
            // panel's `onDismiss`, which routes back through
            // `notifyPanelDismissed()` synchronously — a no-op on the policy
            // here (it is already in `dragging`), so the live drag survives.
            // Deliberately no per-drag reset: the drag is still ongoing and a
            // re-approach must re-arm.
            panel.hide()
        }
    }

    private func onDwellElapsed() {
        apply(policy.handle(.dwellElapsed))
    }

    // MARK: - Helpers

    /// The full frame of the screen the pointer is on (AppKit coordinates, so
    /// it lines up with ``DragObserving``'s pointer and the policy's edge
    /// test). When the pointer lies on no screen's half-open frame — notably
    /// the exact top row (`y == frame.maxY`) of a secondary screen — the
    /// *nearest* screen is chosen (``SuttoDomain/Screen/containing(_:in:)``)
    /// rather than the primary, so the edge check runs against the screen the
    /// pointer is really on. `nil` only when no display is attached.
    private func screenFrame(containing point: PixelPoint) -> PixelRect? {
        Screen.containing(point, in: screens.screens())?.frame
    }

    private func resetDragTracking() {
        capturedWindow = nil
        initialOrigin = nil
        windowMoveConfirmed = false
        forwardedDragBegan = false
    }

    private func resetThrottle() {
        throttlePending = nil
        throttleCoolingDown = false
    }
}
