/// The edge-drag trigger state machine, as a pure deterministic reducer.
///
/// This is the macOS port of the GNOME version's `DragCoordinator`
/// (`src/composition/drag/drag-coordinator.ts`), which watches a window
/// being dragged and pops the layout panel once the pointer dwells at a
/// screen edge. GNOME's coordinator carried two booleans (`isDragging`,
/// `isAtEdge`) plus an external "is the panel visible" query; this policy
/// folds the same information into an explicit ``State`` enum.
///
/// **Pure and clock-free.** The policy owns no timer and reads no clock. It
/// consumes discrete ``Event``s and returns an ``Effect`` for the Operations
/// layer to carry out — including arming and cancelling the dwell timer. The
/// dwell duration itself (GNOME's `EDGE_DELAY = 200 ms`) lives with that
/// timer in Operations, deliberately not here: the policy only learns the
/// dwell elapsed when Operations feeds back a ``Event/dwellElapsed``.
///
/// **Window-agnostic.** GNOME's coordinator tracked the dragged
/// `Meta.Window`; this policy does not. Operations captures the dragged
/// window at show time via its existing `PanelTargetSession`, so the geometry
/// state machine stays free of any window identity.
///
/// **Sampling model.** GNOME polled the pointer every `MONITOR_INTERVAL`
/// (50 ms). On macOS the pointer is delivered event-driven through `NSEvent`
/// drag events, so there is no poll interval in the domain: the policy simply
/// processes each ``Event/pointerMoved(_:screenFrame:)`` it is handed.
public struct EdgeTriggerPolicy: Equatable, Sendable {
    /// Where the drag interaction currently sits.
    public enum State: Equatable, Sendable {
        /// No drag in progress and no panel shown.
        case idle
        /// A window is being dragged; the pointer is not (yet) at an edge.
        case dragging
        /// The pointer has reached an edge while dragging and is dwelling
        /// there; the dwell timer is armed but the panel is not shown yet.
        case atEdgeHolding
        /// The panel has been shown. `dragging` records whether the drag
        /// that triggered it is still in progress. While it is, a pointer
        /// move that stays within the edge band follows the cursor, while a
        /// move that leaves the band does NOT hide the panel outright: it
        /// starts a grace timer and enters ``triggeredPendingHide`` (the user
        /// may only have dipped away momentarily). Once the drag ends the
        /// panel stays put and leaving the edge no longer matters; UI
        /// dismissal governs it.
        case triggered(dragging: Bool)
        /// The panel is shown, the drag is still live, but the pointer has
        /// left the edge band and a grace timer is running. This mirrors the
        /// panel's own auto-hide grace: a brief dip off the edge should not
        /// flick the panel away. Re-entering the edge before the grace
        /// elapses cancels the timer and returns to ``triggered(dragging:)``
        /// with the panel kept; letting the grace elapse
        /// (``Event/hideTimerElapsed``) hides the panel and drops back to
        /// ``dragging`` so a re-approach can re-trigger within the same drag.
        /// The panel keeps following the cursor throughout the grace. Only
        /// reachable while dragging — never after the drop.
        case triggeredPendingHide
    }

    /// Discrete inputs fed to the policy by the Operations layer.
    public enum Event: Equatable, Sendable {
        /// A window drag started (GNOME's `onGrabOpBegin` with
        /// `GrabOp.MOVING`).
        case dragBegan
        /// The pointer moved to `point`, with `screenFrame` being the full
        /// frame of the screen it is currently on. The policy runs the edge
        /// check (``EdgeDetector``) itself so that geometry stays the single
        /// source of truth. Both values are in the same coordinate space
        /// (Operations passes AppKit global coordinates and the screen
        /// frame).
        case pointerMoved(PixelPoint, screenFrame: PixelRect)
        /// The dwell timer armed by ``Effect/armDwellTimer`` has elapsed.
        case dwellElapsed
        /// The leave-edge grace timer armed by ``Effect/armHideTimer`` has
        /// elapsed: the pointer stayed off the edge for the whole grace, so
        /// the panel is now hidden.
        case hideTimerElapsed
        /// The window drag ended (GNOME's `onGrabOpEnd`).
        case dragEnded
        /// The panel was dismissed — a layout was selected, or it auto-hid,
        /// or it was closed. Returns the policy to ``State/idle``.
        case panelDismissed
    }

    /// What the Operations layer must do in response to an event.
    public enum Effect: Equatable, Sendable {
        /// Nothing to do.
        case none
        /// Start the dwell timer; when it elapses, feed back
        /// ``Event/dwellElapsed``.
        case armDwellTimer
        /// Cancel the pending dwell timer, if any.
        case cancelDwellTimer
        /// Start the leave-edge grace timer; when it elapses, feed back
        /// ``Event/hideTimerElapsed``. Armed when the pointer leaves the edge
        /// band while the panel is up and the drag is live — the grace lets a
        /// momentary dip off the edge pass without dismissing the panel.
        case armHideTimer
        /// Cancel the pending leave-edge grace timer, if any.
        case cancelHideTimer
        /// Show the panel at `point` (the current pointer position).
        case showPanel(at: PixelPoint)
        /// Move the already-shown panel to `point` (cursor-follow during
        /// drag).
        case movePanel(to: PixelPoint)
        /// Hide the panel. Emitted when the leave-edge grace fully elapses
        /// with the pointer still off the edge (``Event/hideTimerElapsed``) —
        /// the user really did pull away, so the panel is dismissed and the
        /// interaction drops back to plain dragging, ready to re-arm on a
        /// fresh approach.
        case hidePanel
    }

    /// The current state of the interaction.
    public private(set) var state: State = .idle

    private let edgeDetector: EdgeDetector

    /// The most recent pointer position, remembered so that
    /// ``Event/dwellElapsed`` — which carries no point of its own — can show
    /// the panel at the current cursor.
    private var lastPoint: PixelPoint?

    public init(edgeDetector: EdgeDetector = EdgeDetector()) {
        self.edgeDetector = edgeDetector
    }

    /// The threshold used by the underlying ``EdgeDetector``.
    public var threshold: Double { edgeDetector.threshold }

    /// Advance the state machine by one event, returning the effect the
    /// Operations layer must execute.
    public mutating func handle(_ event: Event) -> Effect {
        switch event {
        case .dragBegan:
            return handleDragBegan()
        case let .pointerMoved(point, screenFrame):
            return handlePointerMoved(point, screenFrame: screenFrame)
        case .dwellElapsed:
            return handleDwellElapsed()
        case .hideTimerElapsed:
            return handleHideTimerElapsed()
        case .dragEnded:
            return handleDragEnded()
        case .panelDismissed:
            return handlePanelDismissed()
        }
    }

    private mutating func handleDragBegan() -> Effect {
        switch state {
        case .idle:
            state = .dragging
        case .triggered:
            // A new drag started while the previous panel is still up: keep
            // the panel and mark the drag live again so it can follow the
            // cursor. (GNOME re-enters the grab without hiding the panel.)
            state = .triggered(dragging: true)
        case .dragging, .atEdgeHolding, .triggeredPendingHide:
            // Already dragging — nothing to do. This should not happen in
            // practice (a drag cannot begin while one is in progress, and the
            // pending-hide phase is only reachable mid-drag).
            break
        }
        return .none
    }

    private mutating func handlePointerMoved(
        _ point: PixelPoint,
        screenFrame: PixelRect
    ) -> Effect {
        lastPoint = point
        let atEdge = edgeDetector.isAtEdge(point, of: screenFrame)

        switch state {
        case .idle:
            // Not dragging: pointer movement is not our concern.
            return .none

        case .dragging:
            // Reaching an edge (a fresh transition, since `dragging` means we
            // were not at one) arms the dwell timer.
            if atEdge {
                state = .atEdgeHolding
                return .armDwellTimer
            }
            return .none

        case .atEdgeHolding:
            if atEdge {
                // Still at the edge: the timer is already armed, so we must
                // not re-arm it (re-arm prevention for a pointer that lingers
                // or jitters while staying within the threshold).
                return .none
            }
            // Left the edge before the panel was shown: back to plain
            // dragging and cancel the pending timer.
            state = .dragging
            return .cancelDwellTimer

        case let .triggered(dragging):
            guard dragging else {
                // The drag already ended: the panel neither follows the
                // cursor nor hides on leaving the edge — the drag is over, so
                // UI dismissal (auto-hide, click-outside, Escape, selection)
                // governs it from here.
                return .none
            }
            if atEdge {
                // Still within the edge band: the panel follows the cursor.
                return .movePanel(to: point)
            }
            // Left the edge band mid-drag: do NOT hide immediately — a small
            // dip off the edge should not flick the panel away. Start the
            // grace timer (matching the panel's auto-hide grace) and enter the
            // pending-hide phase, keeping the panel up. The panel keeps
            // following the cursor on subsequent off-edge moves (below); the
            // arm is emitted only on this entering transition so the effect
            // stays a single value.
            state = .triggeredPendingHide
            return .armHideTimer

        case .triggeredPendingHide:
            if atEdge {
                // Returned to the edge within the grace: cancel the pending
                // hide and keep the panel, back to the live-drag triggered
                // state. (movePanel resumes on the next at-edge move; the
                // cancel is emitted alone on this leaving transition.)
                state = .triggered(dragging: true)
                return .cancelHideTimer
            }
            // Still off the edge while the grace runs: keep following the
            // cursor so the panel does not freeze mid-grace, staying pending.
            return .movePanel(to: point)
        }
    }

    private mutating func handleDwellElapsed() -> Effect {
        // Only a live at-edge dwell shows the panel. A stale timer that fires
        // after the pointer left the edge (or the drag ended) lands in some
        // other state and is ignored — GNOME's timer callback likewise
        // double-checks `isAtEdge && isDragging` before firing.
        guard case .atEdgeHolding = state, let point = lastPoint else {
            return .none
        }
        state = .triggered(dragging: true)
        return .showPanel(at: point)
    }

    private mutating func handleHideTimerElapsed() -> Effect {
        // Only a live pending-hide grace hides the panel. A stale timer that
        // fires after the pointer returned to the edge, the drag ended, or the
        // panel was dismissed lands in some other state and is ignored — the
        // same double-check guard as the dwell timer above.
        guard case .triggeredPendingHide = state else {
            return .none
        }
        // The grace elapsed with the pointer still off the edge: hide and drop
        // back to plain dragging (NOT idle). The drag stays live, so
        // re-approaching an edge and dwelling re-triggers within the same drag.
        state = .dragging
        return .hidePanel
    }

    private mutating func handleDragEnded() -> Effect {
        switch state {
        case .idle:
            return .none
        case .dragging:
            // No timer is armed in plain dragging, but cancel unconditionally
            // to mirror GNOME's `onGrabOpEnd` clearing the timer.
            state = .idle
            return .cancelDwellTimer
        case .atEdgeHolding:
            // A dwell timer is armed and must be cancelled before it fires.
            state = .idle
            return .cancelDwellTimer
        case .triggered:
            // The panel stays shown after the drag ends; it is dismissed
            // later by selection / auto-hide. No timer is pending, so there
            // is nothing to cancel and, crucially, nothing to hide.
            state = .triggered(dragging: false)
            return .none
        case .triggeredPendingHide:
            // The drop keeps the panel for layout selection, so the leave-edge
            // grace no longer applies: cancel it and settle in the dropped
            // triggered state. From here UI dismissal (auto-hide, click,
            // Escape, selection) governs the panel, not the edge.
            state = .triggered(dragging: false)
            return .cancelHideTimer
        }
    }

    private mutating func handlePanelDismissed() -> Effect {
        // A dismissal returns to idle only while the panel is up (`triggered`
        // or `triggeredPendingHide`); from any other state (idle / dragging /
        // atEdgeHolding) it is a no-op and leaves the state untouched. This is
        // load-bearing for re-entrancy: when the policy emits `hidePanel` and
        // transitions to `dragging`, the panel's own dismissal callback feeds
        // `panelDismissed` straight back in while we are already in `dragging`
        // — that MUST be a no-op so the live drag survives and a re-approach
        // can re-arm.
        switch state {
        case .triggered:
            state = .idle
            lastPoint = nil
            return .none
        case .triggeredPendingHide:
            // A genuine external dismissal while the grace was running: also
            // cancel the pending hide timer so it cannot fire into idle.
            state = .idle
            lastPoint = nil
            return .cancelHideTimer
        case .idle, .dragging, .atEdgeHolding:
            return .none
        }
    }
}
