import SuttoDomain
import Testing

@testable import SuttoOperations

/// A `PermissionChecking` stub with a scriptable status, standing in for
/// the AX-backed checker from the infra layer.
@MainActor
private final class PermissionCheckerStub: PermissionChecking {
    var status: AccessibilityAuthorization
    private(set) var requestCount = 0

    init(status: AccessibilityAuthorization) {
        self.status = status
    }

    func currentStatus() -> AccessibilityAuthorization {
        status
    }

    func requestPermission() {
        requestCount += 1
    }
}

@Suite @MainActor struct AccessibilityPermissionUseCaseTests {
    @Test func reportsTheCheckerStatus() {
        let checker = PermissionCheckerStub(status: .denied)
        let useCase = AccessibilityPermissionUseCase(checker: checker)

        #expect(useCase.currentStatus() == .denied)

        checker.status = .granted
        #expect(useCase.currentStatus() == .granted)
    }

    @Test func forwardsPermissionRequestsToTheChecker() {
        let checker = PermissionCheckerStub(status: .denied)
        let useCase = AccessibilityPermissionUseCase(checker: checker)

        useCase.requestPermission()

        #expect(checker.requestCount == 1)
    }

    @Test func presentsOnboardingOnlyWhilePermissionIsDenied() {
        let checker = PermissionCheckerStub(status: .denied)
        let useCase = AccessibilityPermissionUseCase(checker: checker)

        #expect(useCase.shouldPresentOnboarding())
        #expect(!useCase.isOnboardingComplete())

        checker.status = .granted
        #expect(!useCase.shouldPresentOnboarding())
        #expect(useCase.isOnboardingComplete())
    }
}
