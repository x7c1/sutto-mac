import Foundation

/// Whether the app is registered to launch at login, as last reported by the
/// operating system.
///
/// The four cases mirror the states a main-app login item can be in. The OS
/// is the only source of truth: nothing persists this value, and callers read
/// it fresh whenever they render it, so it cannot drift from what launchd
/// actually does (the user can turn the item off in System Settings at any
/// time).
///
/// Keeps the settings pane's wording and checkbox state out of the view, the
/// way `LicensePresentation` does for the License tab.
public enum LaunchAtLoginStatus: Equatable, Sendable {
    /// Registered and allowed to run at login.
    case enabled

    /// Not registered.
    case notRegistered

    /// Registered, but the user has blocked the item in System Settings, so it
    /// will not run until they approve it there.
    case requiresApproval

    /// The registration points at an app bundle that no longer exists (for
    /// example, a development bundle that was removed). Treated as off;
    /// enabling again registers the running bundle.
    case notFound

    /// Whether the "Launch at login" checkbox is shown checked. True when the
    /// app is registered, including when approval is still pending — the user
    /// did ask for it, and unchecking is how they withdraw that request.
    public var isEnabled: Bool {
        switch self {
        case .enabled, .requiresApproval: return true
        case .notRegistered, .notFound: return false
        }
    }

    /// Whether the user has to approve the item in System Settings before it
    /// runs at login.
    public var needsApproval: Bool {
        self == .requiresApproval
    }

    /// The hint shown under the checkbox, or `nil` when there is nothing to
    /// explain. Only the approval case has one.
    public var hint: String? {
        guard needsApproval else { return nil }
        return "Sutto is registered but blocked from launching at login. "
            + "Allow it under System Settings › General › Login Items & Extensions."
    }
}
