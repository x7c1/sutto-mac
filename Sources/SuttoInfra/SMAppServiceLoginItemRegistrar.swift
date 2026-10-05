import OSLog
import ServiceManagement
import SuttoDomain
import SuttoOperations

/// Registers the running app bundle as a login item through
/// `SMAppService.mainApp` (macOS 13+), the conventional mechanism for GUI
/// apps. The OS then lists the app under System Settings › General › Login
/// Items & Extensions, where the user can also turn it off.
///
/// Not unit-tested: it talks to launchd. The registration targets the bundle
/// that is running, so a development build registers `.build/Sutto.app`.
@MainActor
public struct SMAppServiceLoginItemRegistrar: LoginItemRegistering {
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "login-item")

    public init() {}

    public func currentStatus() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .notRegistered
        @unknown default: return .notRegistered
        }
    }

    public func register() throws {
        do {
            try SMAppService.mainApp.register()
            logger.info("registered as a login item")
        } catch {
            logger.error(
                "login item registration failed: \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    public func unregister() throws {
        do {
            try SMAppService.mainApp.unregister()
            logger.info("unregistered as a login item")
        } catch {
            logger.error(
                "login item unregistration failed: \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
