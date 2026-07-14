import SuttoDomain
import Testing

@testable import SuttoOperations

/// Confirms ``DragObserving`` is stub-able so later sub-PRs (the edge-trigger
/// orchestration use case) can drive their tests against a stub rather than a
/// live `NSEvent` monitor.
@Suite @MainActor struct DragObservingTests {
    /// A minimal stub: records start/stop and lets the test push drag events
    /// through the captured handler.
    private final class DragObserverStub: DragObserving {
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

        func emit(_ event: DragEvent) {
            handler?(event)
        }
    }

    @Test func stubDeliversEventsToTheHandler() {
        let stub = DragObserverStub()
        var received: [DragEvent] = []

        stub.start { received.append($0) }
        stub.emit(.began(PixelPoint(x: 1, y: 2)))
        stub.emit(.moved(PixelPoint(x: 3, y: 4)))
        stub.emit(.ended)

        #expect(stub.startCount == 1)
        #expect(received == [.began(PixelPoint(x: 1, y: 2)), .moved(PixelPoint(x: 3, y: 4)), .ended])
    }

    @Test func stubStopsDeliveringAfterStop() {
        let stub = DragObserverStub()
        var received: [DragEvent] = []

        stub.start { received.append($0) }
        stub.stop()
        stub.emit(.moved(PixelPoint(x: 5, y: 6)))

        #expect(stub.stopCount == 1)
        #expect(received.isEmpty)
    }
}
