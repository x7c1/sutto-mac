import Testing

@testable import SuttoOperations

@Suite @MainActor struct PanelToggleUseCaseTests {
    @Test func showsThePanelWhenItIsHidden() {
        var shown = 0
        var hidden = 0
        let useCase = PanelToggleUseCase(
            isPanelVisible: { false },
            showPanel: { shown += 1 },
            hidePanel: { hidden += 1 },
            isGateOpen: { true },
            onGateClosed: {}
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
            hidePanel: { hidden += 1 },
            isGateOpen: { true },
            onGateClosed: {}
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
            },
            isGateOpen: { true },
            onGateClosed: {}
        )

        useCase.toggle()
        useCase.toggle()
        useCase.toggle()

        #expect(actions == ["show", "hide", "show"])
    }

    // MARK: - Licensing gate

    @Test func closedGateBlocksTheShowAndReportsItInstead() {
        var shown = 0
        var hidden = 0
        var gateClosed = 0
        let useCase = PanelToggleUseCase(
            isPanelVisible: { false },
            showPanel: { shown += 1 },
            hidePanel: { hidden += 1 },
            isGateOpen: { false },
            onGateClosed: { gateClosed += 1 }
        )

        useCase.toggle()

        #expect(shown == 0)
        #expect(hidden == 0)
        #expect(gateClosed == 1)
    }

    @Test func closedGateStillAllowsHidingAVisiblePanel() {
        // A panel already on screen can always be dismissed, even while the
        // gate is shut — only the show branch is gated.
        var shown = 0
        var hidden = 0
        var gateClosed = 0
        let useCase = PanelToggleUseCase(
            isPanelVisible: { true },
            showPanel: { shown += 1 },
            hidePanel: { hidden += 1 },
            isGateOpen: { false },
            onGateClosed: { gateClosed += 1 }
        )

        useCase.toggle()

        #expect(hidden == 1)
        #expect(shown == 0)
        #expect(gateClosed == 0)
    }

    @Test func gateIsConsultedFreshOnEachToggle() {
        // The gate can open between toggles (e.g. the user activates a license
        // from the entry point the closed gate opened): the next show succeeds.
        var open = false
        var shown = 0
        var gateClosed = 0
        let useCase = PanelToggleUseCase(
            isPanelVisible: { false },
            showPanel: { shown += 1 },
            hidePanel: {},
            isGateOpen: { open },
            onGateClosed: { gateClosed += 1 }
        )

        useCase.toggle()  // closed
        open = true
        useCase.toggle()  // now open

        #expect(gateClosed == 1)
        #expect(shown == 1)
    }
}
