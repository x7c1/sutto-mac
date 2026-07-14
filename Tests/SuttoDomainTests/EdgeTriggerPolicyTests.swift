import Testing

@testable import SuttoDomain

/// State-transition coverage for the edge-drag trigger policy, mirroring the
/// GNOME `DragCoordinator` semantics it ports. The policy is a pure,
/// clock-free reducer: its effects instruct the Operations layer's dwell
/// timer, so "the timer fired" is modelled by feeding `.dwellElapsed`.
@Suite struct EdgeTriggerPolicyTests {
    // A 100×80 screen at the origin; the default 10 px threshold puts the
    // edges at x∈{0,100}, y∈{0,80}.
    private let screen = PixelRect(x: 0, y: 0, width: 100, height: 80)
    private let edge = PixelPoint(x: 0, y: 40) // on the min-x edge
    private let center = PixelPoint(x: 50, y: 40)

    private func moved(_ point: PixelPoint) -> EdgeTriggerPolicy.Event {
        .pointerMoved(point, screenFrame: screen)
    }

    @Test func startsIdle() {
        let policy = EdgeTriggerPolicy()
        #expect(policy.state == .idle)
    }

    @Test func thresholdIsExposedFromTheDetector() {
        #expect(EdgeTriggerPolicy().threshold == EdgeDetector.defaultThreshold)
        #expect(EdgeTriggerPolicy(edgeDetector: EdgeDetector(threshold: 5)).threshold == 5)
    }

    // MARK: - Behavior 1: drag begins

    @Test func dragBeganMovesToDragging() {
        var policy = EdgeTriggerPolicy()
        let effect = policy.handle(.dragBegan)
        #expect(effect == .none)
        #expect(policy.state == .dragging)
    }

    @Test func pointerMoveWhileIdleIsIgnored() {
        var policy = EdgeTriggerPolicy()
        let effect = policy.handle(moved(edge))
        #expect(effect == .none)
        #expect(policy.state == .idle)
    }

    // MARK: - Behavior 2: reaching an edge arms the dwell timer

    @Test func reachingAnEdgeWhileDraggingArmsTheDwellTimer() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)

        let effect = policy.handle(moved(edge))

        #expect(effect == .armDwellTimer)
        #expect(policy.state == .atEdgeHolding)
    }

    @Test func movingInsideWhileDraggingDoesNothing() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)

        let effect = policy.handle(moved(center))

        #expect(effect == .none)
        #expect(policy.state == .dragging)
    }

    // MARK: - Behavior 3: leaving the edge before the panel shows cancels

    @Test func leavingTheEdgeBeforeDwellCancelsTheTimer() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))

        let effect = policy.handle(moved(center))

        #expect(effect == .cancelDwellTimer)
        #expect(policy.state == .dragging)
    }

    // MARK: - Behavior 4: dwell elapsed shows the panel

    @Test func dwellElapsedAtEdgeShowsThePanelAtTheCurrentPoint() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))

        let effect = policy.handle(.dwellElapsed)

        #expect(effect == .showPanel(at: edge))
        #expect(policy.state == .triggered(dragging: true))
    }

    @Test func staleDwellElapsedAfterLeavingTheEdgeIsIgnored() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))
        _ = policy.handle(moved(center)) // left the edge; timer cancelled

        let effect = policy.handle(.dwellElapsed) // stale fire

        #expect(effect == .none)
        #expect(policy.state == .dragging)
    }

    @Test func dwellElapsedWhileMerelyDraggingIsIgnored() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)

        let effect = policy.handle(.dwellElapsed)

        #expect(effect == .none)
        #expect(policy.state == .dragging)
    }

    // MARK: - Behavior 5: latch + cursor-follow

    @Test func whileTriggeredEachMoveFollowsTheCursor() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))
        _ = policy.handle(.dwellElapsed)

        let target = PixelPoint(x: 30, y: 20)
        let effect = policy.handle(moved(target))

        #expect(effect == .movePanel(to: target))
        #expect(policy.state == .triggered(dragging: true))
    }

    /// Once triggered, leaving the edge must NOT re-arm, cancel, or hide —
    /// the panel just follows the cursor (dismissal-prevention latch).
    @Test func leavingTheEdgeWhileTriggeredDoesNotCancelOrHide() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))
        _ = policy.handle(.dwellElapsed)

        let effect = policy.handle(moved(center)) // well off the edge

        #expect(effect == .movePanel(to: center))
        #expect(policy.state == .triggered(dragging: true))
    }

    // MARK: - Behavior 6: drag end keeps a shown panel

    @Test func dragEndWhileTriggeredKeepsThePanelShown() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))
        _ = policy.handle(.dwellElapsed)

        let effect = policy.handle(.dragEnded)

        #expect(effect == .none) // no hide
        #expect(policy.state == .triggered(dragging: false))
    }

    @Test func afterDragEndAShownPanelStopsFollowingTheCursor() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))
        _ = policy.handle(.dwellElapsed)
        _ = policy.handle(.dragEnded)

        let effect = policy.handle(moved(PixelPoint(x: 30, y: 20)))

        #expect(effect == .none)
        #expect(policy.state == .triggered(dragging: false))
    }

    @Test func panelDismissedReturnsToIdle() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))
        _ = policy.handle(.dwellElapsed)
        _ = policy.handle(.dragEnded)

        let effect = policy.handle(.panelDismissed)

        #expect(effect == .none)
        #expect(policy.state == .idle)
    }

    @Test func dragEndWhileHoldingCancelsTheTimerAndReturnsToIdle() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))

        let effect = policy.handle(.dragEnded)

        #expect(effect == .cancelDwellTimer)
        #expect(policy.state == .idle)
    }

    @Test func dragEndWhileMerelyDraggingReturnsToIdle() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)

        let effect = policy.handle(.dragEnded)

        #expect(effect == .cancelDwellTimer)
        #expect(policy.state == .idle)
    }

    // MARK: - Behavior 7: no duplicate arm / show under jitter

    @Test func stayingAtTheEdgeAcrossMovesArmsTheTimerOnlyOnce() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)

        let first = policy.handle(moved(PixelPoint(x: 2, y: 40)))
        let second = policy.handle(moved(PixelPoint(x: 5, y: 40)))
        let third = policy.handle(moved(PixelPoint(x: 8, y: 40)))

        #expect(first == .armDwellTimer)
        #expect(second == .none)
        #expect(third == .none)
        #expect(policy.state == .atEdgeHolding)
    }

    /// A pointer oscillating around the threshold after the panel is shown
    /// never produces a second `showPanel` (or any arm/cancel) — only follow
    /// moves.
    @Test func jitterWhileTriggeredNeverShowsThePanelAgain() {
        var policy = EdgeTriggerPolicy()
        _ = policy.handle(.dragBegan)
        _ = policy.handle(moved(edge))
        _ = policy.handle(.dwellElapsed)

        let jitter = [
            PixelPoint(x: 5, y: 40), // at edge
            PixelPoint(x: 20, y: 40), // off edge
            PixelPoint(x: 3, y: 40), // at edge again
            PixelPoint(x: 50, y: 40), // center
        ]
        for point in jitter {
            let effect = policy.handle(moved(point))
            #expect(effect == .movePanel(to: point))
        }
        // A late dwell timer that somehow survived must not re-show.
        #expect(policy.handle(.dwellElapsed) == .none)
        #expect(policy.state == .triggered(dragging: true))
    }

    // MARK: - Behavior 8: all four edges trigger

    @Test func allFourEdgesArmTheTimer() {
        let edges = [
            PixelPoint(x: 0, y: 40), // min-x
            PixelPoint(x: 100, y: 40), // max-x
            PixelPoint(x: 50, y: 0), // min-y
            PixelPoint(x: 50, y: 80), // max-y
        ]
        for point in edges {
            var policy = EdgeTriggerPolicy()
            _ = policy.handle(.dragBegan)
            let effect = policy.handle(moved(point))
            #expect(effect == .armDwellTimer)
            #expect(policy.state == .atEdgeHolding)
        }
    }
}
