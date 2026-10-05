import SuttoDomain

/// The "Launch Sutto at login" setting: reads the OS registration status and
/// turns it on or off.
///
/// Holds no state of its own — every read goes to the registrar, so the
/// settings pane always reflects what the user last did, whether in Sutto or
/// in System Settings. Opt-in only: nothing registers the app unless
/// ``setEnabled(_:)`` is called from the user's toggle.
@MainActor
public final class LaunchAtLoginUseCase {
    private let registrar: any LoginItemRegistering

    public init(registrar: any LoginItemRegistering) {
        self.registrar = registrar
    }

    /// The current registration status, read fresh from the OS.
    public func currentStatus() -> LaunchAtLoginStatus {
        registrar.currentStatus()
    }

    /// Registers (`true`) or unregisters (`false`) the app as a login item.
    ///
    /// A no-op when the status already matches the request: enabling an
    /// item that is registered (even if still awaiting approval) does not
    /// register it again, and disabling an item that is not registered (or
    /// whose registration points at a missing bundle) does not unregister.
    /// Enabling from ``LaunchAtLoginStatus/notFound`` registers the running
    /// bundle afresh.
    ///
    /// - Throws: whatever the registrar throws; the registration is then
    ///   left as the OS has it, and ``currentStatus()`` reports that.
    public func setEnabled(_ enabled: Bool) throws {
        guard registrar.currentStatus().isEnabled != enabled else { return }
        if enabled {
            try registrar.register()
        } else {
            try registrar.unregister()
        }
    }

    /// Opens the Login Items pane of System Settings, where an item awaiting
    /// approval can be allowed.
    public func openLoginItemsSettings() {
        registrar.openLoginItemsSettings()
    }
}
