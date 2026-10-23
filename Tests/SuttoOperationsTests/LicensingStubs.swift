import Foundation
import SuttoDomain

@testable import SuttoOperations

/// In-memory ``LicenseRepository`` for gate tests: `load()` serves the scripted
/// state and counts calls (to prove the lazy load happens once), `save(_:)`
/// records every persisted state and can be scripted to fail — the same shape
/// as ``InMemoryLayoutHistoryRepository``.
@MainActor
final class InMemoryLicenseRepository: LicenseRepository {
    var storedState: LicenseState
    var saveError: Error?
    private(set) var loadCount = 0
    private(set) var savedStates: [LicenseState] = []

    init(state: LicenseState = .freshTrial(now: Date(timeIntervalSince1970: 1_700_000_000))) {
        storedState = state
    }

    func load() -> LicenseState {
        loadCount += 1
        return storedState
    }

    func save(_ state: LicenseState) throws {
        if let saveError {
            throw saveError
        }
        storedState = state
        savedStates.append(state)
    }
}

/// Scriptable ``LicenseApiClient`` for gate tests: each call returns its
/// scripted outcome and records how it was invoked. This is the stub the
/// "the API can disappear and a valid device keeps working" tests drive.
@MainActor
final class StubLicenseApiClient: LicenseApiClient {
    var validationOutcome: ValidationOutcome = .noResponse
    var activationOutcome: ActivationOutcome = .noResponse
    /// Runs inside `validate` before it returns, standing in for whatever the
    /// app does on the main actor while the real request is in flight.
    var duringValidate: (@MainActor () -> Void)?
    /// Like ``duringValidate``, but may await — for work that is itself async,
    /// such as an activation finishing while the request is in flight.
    var duringValidateAsync: (@MainActor () async -> Void)?
    private(set) var validateCount = 0
    private(set) var activateCount = 0
    private(set) var lastActivateKey: String?
    private(set) var lastActivateDevice: DeviceIdentity?
    private(set) var lastValidateKey: String?
    private(set) var lastValidateActivationId: String?

    func activate(key: String, device: DeviceIdentity) async -> ActivationOutcome {
        activateCount += 1
        lastActivateKey = key
        lastActivateDevice = device
        return activationOutcome
    }

    func validate(key: String, activationId: String) async -> ValidationOutcome {
        validateCount += 1
        lastValidateKey = key
        lastValidateActivationId = activationId
        duringValidate?()
        await duringValidateAsync?()
        return validationOutcome
    }
}

/// Scriptable ``ConnectivityMonitoring`` for gate tests: `isOnline` is set
/// directly, and ``report(isOnline:)`` plays a connectivity change the way the
/// `NWPathMonitor` adapter delivers one.
@MainActor
final class StubConnectivity: ConnectivityMonitoring {
    private(set) var isOnline: Bool
    private var onChange: (@MainActor (Bool) -> Void)?

    init(isOnline: Bool) {
        self.isOnline = isOnline
    }

    func startWatching(_ onChange: @escaping @MainActor (_ isOnline: Bool) -> Void) {
        self.onChange = onChange
    }

    /// Changes the connectivity without a callback, as if nobody watched.
    func set(isOnline: Bool) {
        self.isOnline = isOnline
    }

    /// Changes the connectivity and calls the watcher, if any.
    func report(isOnline: Bool) {
        self.isOnline = isOnline
        onChange?(isOnline)
    }
}
