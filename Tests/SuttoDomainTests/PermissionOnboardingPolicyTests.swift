import Testing

@testable import SuttoDomain

@Suite struct PermissionOnboardingPolicyTests {
    @Test func presentsOnboardingWhenPermissionIsDenied() {
        #expect(PermissionOnboardingPolicy.shouldPresent(for: .denied))
    }

    @Test func skipsOnboardingWhenPermissionIsGranted() {
        #expect(!PermissionOnboardingPolicy.shouldPresent(for: .granted))
    }

    @Test func completesOnboardingOnceGranted() {
        #expect(PermissionOnboardingPolicy.isComplete(for: .granted))
    }

    @Test func keepsOnboardingWhilePermissionIsDenied() {
        #expect(!PermissionOnboardingPolicy.isComplete(for: .denied))
    }
}
