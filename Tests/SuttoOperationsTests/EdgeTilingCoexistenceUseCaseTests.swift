import Testing

@testable import SuttoOperations

@Suite @MainActor struct EdgeTilingCoexistenceUseCaseTests {
    /// A scriptable ``EdgeTilingDetecting`` stub.
    private final class DetectorStub: EdgeTilingDetecting {
        var enabled: Bool
        init(enabled: Bool) { self.enabled = enabled }
        func isSystemEdgeTilingEnabled() -> Bool { enabled }
    }

    @Test func warnsWhileSystemTilingIsEnabled() {
        let useCase = EdgeTilingCoexistenceUseCase(detector: DetectorStub(enabled: true))
        #expect(useCase.shouldWarn())
    }

    @Test func doesNotWarnWhenSystemTilingIsDisabled() {
        let useCase = EdgeTilingCoexistenceUseCase(detector: DetectorStub(enabled: false))
        #expect(!useCase.shouldWarn())
    }

    /// Read fresh on every call, so a mid-session toggle flips the decision
    /// without rebuilding the use case.
    @Test func reflectsAToggleBetweenCalls() {
        let detector = DetectorStub(enabled: true)
        let useCase = EdgeTilingCoexistenceUseCase(detector: detector)

        #expect(useCase.shouldWarn())

        detector.enabled = false
        #expect(!useCase.shouldWarn())
    }
}
