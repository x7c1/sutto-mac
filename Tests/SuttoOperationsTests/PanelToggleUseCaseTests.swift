import Testing

@testable import SuttoOperations

@Suite @MainActor struct PanelToggleUseCaseTests {
    @Test func showsThePanelWhenItIsHidden() {
        var shown = 0
        var hidden = 0
        let useCase = PanelToggleUseCase(
            isPanelVisible: { false },
            showPanel: { shown += 1 },
            hidePanel: { hidden += 1 }
        )

        useCase.toggle()

        #expect(shown == 1)
        #expect(hidden == 0)
    }

    @Test func hidesThePanelWhenItIsVisible() {
        var shown = 0
        var hidden = 0
        let useCase = PanelToggleUseCase(
            isPanelVisible: { true },
            showPanel: { shown += 1 },
            hidePanel: { hidden += 1 }
        )

        useCase.toggle()

        #expect(shown == 0)
        #expect(hidden == 1)
    }

    @Test func alternatesShowAndHideAsVisibilityTracksTheToggle() {
        var visible = false
        var actions: [String] = []
        let useCase = PanelToggleUseCase(
            isPanelVisible: { visible },
            showPanel: {
                visible = true
                actions.append("show")
            },
            hidePanel: {
                visible = false
                actions.append("hide")
            }
        )

        useCase.toggle()
        useCase.toggle()
        useCase.toggle()

        #expect(actions == ["show", "hide", "show"])
    }
}
