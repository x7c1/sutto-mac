import SuttoDomain

/// Access to the macOS Accessibility permission, as required by the
/// operations layer and implemented by the infra layer.
///
/// Isolated to the main actor because permission state drives UI decisions
/// and the underlying AX APIs are called from the main thread.
@MainActor
public protocol PermissionChecking {
    /// The current state of the Accessibility permission.
    func currentStatus() -> AccessibilityAuthorization

    /// Asks the system to prompt the user for the Accessibility permission.
    func requestPermission()
}
