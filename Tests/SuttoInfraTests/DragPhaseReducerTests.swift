import SuttoDomain
import SuttoOperations
import Testing

@testable import SuttoInfra

/// Unit tests for the raw-phase → ``DragEvent`` derivation extracted from
/// ``NSEventGlobalDragMonitor``. The live monitor itself is not unit-testable
/// (it needs the system event stream), but this state machine is.
@Suite struct DragPhaseReducerTests {
    private let p1 = PixelPoint(x: 10, y: 20)
    private let p2 = PixelPoint(x: 30, y: 40)
    private let p3 = PixelPoint(x: 50, y: 60)

    @Test func firstDragAfterIdleBegins() {
        var reducer = DragPhaseReducer()

        #expect(reducer.reduce(.dragged, at: p1) == .began(p1))
    }

    @Test func subsequentDragsMove() {
        var reducer = DragPhaseReducer()
        _ = reducer.reduce(.dragged, at: p1)

        #expect(reducer.reduce(.dragged, at: p2) == .moved(p2))
        #expect(reducer.reduce(.dragged, at: p3) == .moved(p3))
    }

    @Test func upEndsAnActiveDrag() {
        var reducer = DragPhaseReducer()
        _ = reducer.reduce(.dragged, at: p1)

        #expect(reducer.reduce(.up, at: p2) == .ended)
    }

    @Test func upWithoutADragIsIgnored() {
        var reducer = DragPhaseReducer()

        #expect(reducer.reduce(.up, at: p1) == nil)
    }

    @Test func aNewDragBeginsCleanlyAfterThePreviousEnded() {
        var reducer = DragPhaseReducer()
        _ = reducer.reduce(.dragged, at: p1)
        _ = reducer.reduce(.up, at: p1)

        // The reset on `.up` means the next drag is a fresh `began`, not a
        // stray `moved`.
        #expect(reducer.reduce(.dragged, at: p2) == .began(p2))
    }

    @Test func repeatedUpsAfterAnEndDoNothing() {
        var reducer = DragPhaseReducer()
        _ = reducer.reduce(.dragged, at: p1)
        _ = reducer.reduce(.up, at: p1)

        #expect(reducer.reduce(.up, at: p2) == nil)
    }
}
