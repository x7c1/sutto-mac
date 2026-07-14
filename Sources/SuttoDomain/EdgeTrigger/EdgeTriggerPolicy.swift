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
        /// move that leaves the band hides the panel and drops back to
        /// ``dragging`` (the user changed their mind — a re-approach re-arms
        /// within the same drag). Once the drag ends the panel stays put and
        /// leaving the edge no longer matters; UI dismissal governs it.
        case triggered(dragging: Bool)
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
        /// Show the panel at `point` (the current pointer position).
        case showPanel(at: PixelPoint)
        /// Move the already-shown panel to `point` (cursor-follow during
        /// drag).
        case movePanel(to: PixelPoint)
        /// Hide the panel. Emitted when the pointer leaves the edge band
        /// while the panel is up and the drag is still live — the user is
        /// pulling away, so the panel is dismissed and the interaction drops
        /// back to plain dragging, ready to re-arm on a fresh approach.
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
        case .dragging, .atEdgeHolding:
            // Already dragging — nothing to do. This should not happen in
            // practice (a drag cannot begin while one is in progress).
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
            // Left the edge band mid-drag: the user is pulling away, so hide
            // the panel and drop back to plain dragging (NOT idle). The drag
            // stays live, so re-approaching an edge and dwelling re-triggers
            // the panel within the same drag.
            state = .dragging
            return .hidePanel
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
        }
    }

    private mutating func handlePanelDismissed() -> Effect {
        // A dismissal returns to idle only while the panel is up; from any
        // other state (idle / dragging / atEdgeHolding) it is a no-op and
        // leaves the state untouched. This is load-bearing for re-entrancy:
        // when the policy emits `hidePanel` and transitions to `dragging`,
        // the panel's own dismissal callback feeds `panelDismissed` straight
        // back in while we are already in `dragging` — that MUST be a no-op
        // so the live drag survives and a re-approach can re-arm.
        guard case .triggered = state else {
            return .none
        }
        state = .idle
        lastPoint = nil
        return .none
    }
}
