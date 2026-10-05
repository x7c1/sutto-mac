import SuttoDomain
import Testing

@testable import SuttoOperations

private struct RegistrarError: Error {}

/// A `LoginItemRegistering` stub with a scriptable status, standing in for
/// the `SMAppService`-backed registrar. A successful register/unregister
/// moves the status the way the OS would; a failing one leaves it alone.
@MainActor
private final class LoginItemRegistrarStub: LoginItemRegistering {
    var status: LaunchAtLoginStatus
    var failing = false
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func currentStatus() -> LaunchAtLoginStatus {
        status
    }

    func register() throws {
        registerCount += 1
        if failing { throw RegistrarError() }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if failing { throw RegistrarError() }
        status = .notRegistered
    }

    func openLoginItemsSettings() {
        openSettingsCount += 1
    }
}

/// The toggle across every state the OS can report when the user flips it:
/// enabling registers only when not already registered, disabling
/// unregisters only when registered, and failures propagate without any
/// cached flag hiding the real status.
@Suite @MainActor struct LaunchAtLoginUseCaseTests {
    @Test(arguments: [LaunchAtLoginStatus.notRegistered, .notFound])
    func enablingWhenNotRegisteredRegisters(from status: LaunchAtLoginStatus) throws {
        let registrar = LoginItemRegistrarStub(status: status)
        let useCase = LaunchAtLoginUseCase(registrar: registrar)

        try useCase.setEnabled(true)

        #expect(registrar.registerCount == 1)
        #expect(registrar.unregisterCount == 0)
        #expect(useCase.currentStatus() == .enabled)
    }

    @Test(arguments: [LaunchAtLoginStatus.enabled, .requiresApproval])
    func enablingWhenRegisteredIsANoOp(from status: LaunchAtLoginStatus) throws {
        let registrar = LoginItemRegistrarStub(status: status)
        let useCase = LaunchAtLoginUseCase(registrar: registrar)

        try useCase.setEnabled(true)

        #expect(registrar.registerCount == 0)
        #expect(registrar.unregisterCount == 0)
        #expect(useCase.currentStatus() == status)
    }

    @Test(arguments: [LaunchAtLoginStatus.enabled, .requiresApproval])
    func disablingWhenRegisteredUnregisters(from status: LaunchAtLoginStatus) throws {
        let registrar = LoginItemRegistrarStub(status: status)
        let useCase = LaunchAtLoginUseCase(registrar: registrar)

        try useCase.setEnabled(false)

        #expect(registrar.unregisterCount == 1)
        #expect(registrar.registerCount == 0)
        #expect(useCase.currentStatus() == .notRegistered)
    }

    @Test(arguments: [LaunchAtLoginStatus.notRegistered, .notFound])
    func disablingWhenNotRegisteredIsANoOp(from status: LaunchAtLoginStatus) throws {
        let registrar = LoginItemRegistrarStub(status: status)
        let useCase = LaunchAtLoginUseCase(registrar: registrar)

        try useCase.setEnabled(false)

        #expect(registrar.registerCount == 0)
        #expect(registrar.unregisterCount == 0)
        #expect(useCase.currentStatus() == status)
    }

    @Test func aFailingRegisterPropagatesAndKeepsTheRealStatus() {
        let registrar = LoginItemRegistrarStub(status: .notRegistered)
        registrar.failing = true
        let useCase = LaunchAtLoginUseCase(registrar: registrar)

        #expect(throws: RegistrarError.self) { try useCase.setEnabled(true) }
        #expect(registrar.registerCount == 1)
        #expect(useCase.currentStatus() == .notRegistered)
    }

    @Test func aFailingUnregisterPropagatesAndKeepsTheRealStatus() {
        let registrar = LoginItemRegistrarStub(status: .enabled)
        registrar.failing = true
        let useCase = LaunchAtLoginUseCase(registrar: registrar)

        #expect(throws: RegistrarError.self) { try useCase.setEnabled(false) }
        #expect(registrar.unregisterCount == 1)
        #expect(useCase.currentStatus() == .enabled)
    }

    /// No cached flag: a change made outside Sutto (in System Settings) shows
    /// up on the next read.
    @Test func currentStatusReadsTheRegistrarEveryTime() {
        let registrar = LoginItemRegistrarStub(status: .enabled)
        let useCase = LaunchAtLoginUseCase(registrar: registrar)
        #expect(useCase.currentStatus() == .enabled)

        registrar.status = .requiresApproval
        #expect(useCase.currentStatus() == .requiresApproval)

        registrar.status = .notRegistered
        #expect(useCase.currentStatus() == .notRegistered)
    }

    @Test func forwardsOpeningLoginItemsSettings() {
        let registrar = LoginItemRegistrarStub(status: .requiresApproval)
        let useCase = LaunchAtLoginUseCase(registrar: registrar)

        useCase.openLoginItemsSettings()

        #expect(registrar.openSettingsCount == 1)
    }
}
