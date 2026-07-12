/// Pure decision logic for the accessibility-permission onboarding flow.
///
/// The app layer feeds in the current ``AccessibilityAuthorization`` and
/// acts on the answers; keeping the decisions here makes them unit-testable
/// without touching AppKit or the AX APIs.
public enum PermissionOnboardingPolicy {
    /// Whether the onboarding window should be presented for the given
    /// permission state (checked at launch).
    public static func shouldPresent(for status: AccessibilityAuthorization) -> Bool {
        status == .denied
    }

    /// Whether onboarding is complete for the given permission state
    /// (checked by the poll loop while the window is visible).
    public static func isComplete(for status: AccessibilityAuthorization) -> Bool {
        status == .granted
    }
}
