import ApplicationServices
import SuttoDomain
import SuttoOperations

/// Bridges the macOS Accessibility (AX) trust APIs to the domain-level
/// ``AccessibilityAuthorization`` value.
@MainActor
public struct AccessibilityPermissionChecker: PermissionChecking {
    public init() {}

    public func currentStatus() -> AccessibilityAuthorization {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Asks the system to show the standard dialog that offers to open
    /// System Settings with this app pre-listed under Accessibility.
    public func requestPermission() {
        // The literal value of `kAXTrustedCheckOptionPrompt`. Referencing the
        // global directly is rejected under Swift 6 strict concurrency
        // (it is imported as shared mutable state).
        let promptOption = "AXTrustedCheckOptionPrompt"
        let options = [promptOption: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
