import Testing

@testable import SuttoDomain
@testable import SuttoOperations

@Suite @MainActor struct EdgeTilingCoexistenceUseCaseTests {
    /// A scriptable ``EdgeTilingDetecting`` stub.
    private final class DetectorStub: EdgeTilingDetecting {
        var conflicts: EdgeTilingConflicts
        init(conflicts: EdgeTilingConflicts) { self.conflicts = conflicts }
        func detectConflicts() -> EdgeTilingConflicts { conflicts }
    }

    @Test func warnsWhenOnlyEdgeTilingIsEnabled() {
        let useCase = EdgeTilingCoexistenceUseCase(
            detector: DetectorStub(conflicts: EdgeTilingConflicts(edgeTiling: true, menuBarFill: false))
        )
        #expect(useCase.shouldWarn())
    }

    @Test func warnsWhenOnlyMenuBarFillIsEnabled() {
        let useCase = EdgeTilingCoexistenceUseCase(
            detector: DetectorStub(conflicts: EdgeTilingConflicts(edgeTiling: false, menuBarFill: true))
        )
        #expect(useCase.shouldWarn())
    }

    @Test func warnsWhenBothAreEnabled() {
        let useCase = EdgeTilingCoexistenceUseCase(
            detector: DetectorStub(conflicts: EdgeTilingConflicts(edgeTiling: true, menuBarFill: true))
        )
        #expect(useCase.shouldWarn())
    }

    @Test func doesNotWarnWhenNeitherIsEnabled() {
        let useCase = EdgeTilingCoexistenceUseCase(
            detector: DetectorStub(conflicts: EdgeTilingConflicts(edgeTiling: false, menuBarFill: false))
        )
        #expect(!useCase.shouldWarn())
    }

    /// Exposes the conflict set so the guidance window can list the enabled
    /// toggles.
    @Test func currentConflictsReportsTheDetectedSet() {
        let conflicts = EdgeTilingConflicts(edgeTiling: false, menuBarFill: true)
        let useCase = EdgeTilingCoexistenceUseCase(detector: DetectorStub(conflicts: conflicts))
        #expect(useCase.currentConflicts() == conflicts)
    }

    /// Read fresh on every call, so a mid-session toggle flips the decision
    /// without rebuilding the use case.
    @Test func reflectsAToggleBetweenCalls() {
        let detector = DetectorStub(conflicts: EdgeTilingConflicts(edgeTiling: true, menuBarFill: false))
        let useCase = EdgeTilingCoexistenceUseCase(detector: detector)

        #expect(useCase.shouldWarn())

        detector.conflicts = EdgeTilingConflicts(edgeTiling: false, menuBarFill: false)
        #expect(!useCase.shouldWarn())
    }
}
