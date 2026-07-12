/// The state of the macOS Accessibility permission as seen by the app.
///
/// This is a platform-independent value type; the actual AX API calls live
/// in the app layer, which maps their results into this type.
public enum AccessibilityAuthorization: Equatable, Sendable {
    case granted
    case denied
}
