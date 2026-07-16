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

    init(state: LicenseState = .freshTrial) {
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
        return validationOutcome
    }
}
