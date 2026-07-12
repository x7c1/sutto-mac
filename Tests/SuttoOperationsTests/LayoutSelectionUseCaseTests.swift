import SuttoDomain
import Testing

@testable import SuttoOperations

@Suite @MainActor struct LayoutSelectionUseCaseTests {
    private func makeLayout(label: String) -> Layout {
        Layout(
            label: label,
            position: LayoutPosition(x: "0", y: "0"),
            size: LayoutSize(width: "50%", height: "100%")
        )
    }

    @Test func forwardsTheSelectedLayoutToTheHandler() {
        var received: [Layout] = []
        let useCase = LayoutSelectionUseCase { received.append($0) }
        let layout = makeLayout(label: "Left Half")

        useCase.select(layout)

        #expect(received == [layout])
    }

    @Test func forwardsEverySelectionInOrder() {
        var received: [Layout] = []
        let useCase = LayoutSelectionUseCase { received.append($0) }

        useCase.select(makeLayout(label: "Left Half"))
        useCase.select(makeLayout(label: "Right Half"))

        #expect(received.map(\.label) == ["Left Half", "Right Half"])
    }
}
