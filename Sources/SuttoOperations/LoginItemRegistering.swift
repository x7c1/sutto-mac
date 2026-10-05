import SuttoDomain

/// Registration of the app itself as a login item, as required by the
/// operations layer and implemented by the infra layer.
///
/// Isolated to the main actor because it is driven from the settings window.
@MainActor
public protocol LoginItemRegistering {
    /// The registration status as the OS reports it right now.
    func currentStatus() -> LaunchAtLoginStatus

    /// Registers the running app to launch at login.
    func register() throws

    /// Removes the app's login item registration.
    func unregister() throws

    /// Opens System Settings at the Login Items pane, where the user can
    /// approve or remove the item.
    func openLoginItemsSettings()
}
