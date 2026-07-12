import SuttoDomain

/// Coordinates the Accessibility permission state for the UI layer.
///
/// Combines the live permission status (from a ``PermissionChecking``
/// implementation, injected by the composition root) with the pure
/// ``PermissionOnboardingPolicy`` decisions, so the UI never talks to the
/// checker or the policy directly.
@MainActor
public final class AccessibilityPermissionUseCase {
    private let checker: any PermissionChecking

    public init(checker: any PermissionChecking) {
        self.checker = checker
    }

    /// The current state of the Accessibility permission.
    public func currentStatus() -> AccessibilityAuthorization {
        checker.currentStatus()
    }

    /// Asks the system to prompt the user for the Accessibility permission.
    public func requestPermission() {
        checker.requestPermission()
    }

    /// Whether the onboarding window should be presented (checked at launch).
    public func shouldPresentOnboarding() -> Bool {
        PermissionOnboardingPolicy.shouldPresent(for: checker.currentStatus())
    }

    /// Whether onboarding is complete (checked by the poll loop while the
    /// onboarding window is visible).
    public func isOnboardingComplete() -> Bool {
        PermissionOnboardingPolicy.isComplete(for: checker.currentStatus())
    }
}
