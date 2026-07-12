import SuttoDomain
import Testing

@testable import SuttoOperations

@Suite @MainActor struct LayoutSelectionUseCaseTests {
    private func makeEvent(label: String, displayKey: String = "0") -> LayoutSelectedEvent {
        LayoutSelectedEvent(
            layout: Layout(
                label: label,
                position: LayoutPosition(x: "0", y: "0"),
                size: LayoutSize(width: "50%", height: "100%")
            ),
            displayKey: displayKey
        )
    }

    @Test func forwardsTheSelectedEventToTheHandler() {
        var received: [LayoutSelectedEvent] = []
        let useCase = LayoutSelectionUseCase { received.append($0) }
        let event = makeEvent(label: "Left Half", displayKey: "1")

        useCase.select(event)

        #expect(received == [event])
        #expect(received.first?.displayKey == "1")
    }

    @Test func forwardsEverySelectionInOrder() {
        var received: [LayoutSelectedEvent] = []
        let useCase = LayoutSelectionUseCase { received.append($0) }

        useCase.select(makeEvent(label: "Left Half"))
        useCase.select(makeEvent(label: "Right Half", displayKey: "1"))

        #expect(received.map(\.layout.label) == ["Left Half", "Right Half"])
        #expect(received.map(\.displayKey) == ["0", "1"])
    }
}
