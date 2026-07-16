import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

/// The gate behaviour of ``LicenseGate``: the operations wrapper that composes
/// the pure ``LicenseGatePolicy`` and ``ValidationOutcome`` mapping with
/// persistence, the API client, and injected clocks.
///
/// The centrepiece is the fail-open fixture — a valid device stays open (and
/// its status untouched, unsaved) when validate cannot get an authoritative
/// answer — pinned here against the operations layer, the operations-level
/// counterpart to the design's "the API can disappear" fixture.
@Suite @MainActor struct LicenseGateTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)
    private let device = DeviceIdentity(id: "device-1", label: "Test Mac")

    private func makeGate(
        repository: InMemoryLicenseRepository,
        apiClient: StubLicenseApiClient,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) },
        today: @escaping () -> String = { "2026-07-16" }
    ) -> LicenseGate {
        LicenseGate(
            repository: repository, apiClient: apiClient, device: device, now: now, today: today)
    }

    private func validState(status: LicenseStatus = .valid) -> LicenseState {
        LicenseState(
            status: status,
            record: LicenseRecord(
                licenseKey: "KEY-123",
                activationId: "ACT-456",
                validUntil: t0,
                lastValidated: t0,
                status: status
            ),
            trial: .initial
        )
    }

    private func trialState(daysUsed: Int, lastUsedDate: String) -> LicenseState {
        LicenseState(
            status: .trial, record: nil,
            trial: TrialState(daysUsed: daysUsed, lastUsedDate: lastUsedDate))
    }

    // MARK: - Fail-open: no authoritative answer never downgrades

    /// The most important case: a valid device whose launch validate gets no
    /// authoritative answer stays open, keeps `valid`, and writes nothing.
    @Test func validDeviceStaysOpenWhenValidateHasNoResponse() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .noResponse
        let gate = makeGate(repository: repository, apiClient: apiClient)

        await gate.validateOnLaunch()

        #expect(gate.isOpen())
        #expect(gate.state().status == .valid)
        // Fail-open leaves the cached status alone, so nothing is persisted.
        #expect(repository.savedStates.isEmpty)
    }

    @Test func launchValidatePassesTheStoredKeyAndActivation() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient)

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 1)
        #expect(apiClient.lastValidateKey == "KEY-123")
        #expect(apiClient.lastValidateActivationId == "ACT-456")
    }

    // MARK: - Fail-open: authoritative NO downgrades

    @Test func validDeviceClosesWhenValidateRejectsAsExpired() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .rejected(.expired)
        let gate = makeGate(repository: repository, apiClient: apiClient)

        await gate.validateOnLaunch()

        #expect(!gate.isOpen())
        #expect(gate.state().status == .expired)
        #expect(repository.savedStates.last?.status == .expired)
    }

    @Test func validDeviceClosesWhenValidateRejectsAsDeactivated() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .rejected(.deactivated)
        let gate = makeGate(repository: repository, apiClient: apiClient)

        await gate.validateOnLaunch()

        #expect(!gate.isOpen())
        #expect(gate.state().status == .expired)
    }

    @Test func validDeviceBecomesInvalidWhenValidateRejectsTheKey() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .rejected(.invalidKey)
        let gate = makeGate(repository: repository, apiClient: apiClient)

        await gate.validateOnLaunch()

        #expect(!gate.isOpen())
        #expect(gate.state().status == .invalid)
    }

    /// A confirming validate refreshes the record's expiry and last-validated
    /// timestamp and keeps the device valid.
    @Test func validateRefreshesTheRecordOnConfirmation() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        let refreshed = Date(timeIntervalSince1970: 2_000_000_000)
        apiClient.validationOutcome = .valid(validUntil: refreshed)
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { self.t1 })

        await gate.validateOnLaunch()

        #expect(gate.state().status == .valid)
        #expect(gate.state().record?.validUntil == refreshed)
        #expect(gate.state().record?.lastValidated == t1)
        #expect(repository.savedStates.last?.record?.validUntil == refreshed)
    }

    @Test func launchValidateSkipsWhenNotValid() async {
        let repository = InMemoryLicenseRepository(state: trialState(daysUsed: 0, lastUsedDate: ""))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient)

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 0)
    }

    @Test func launchValidateSkipsWhenNoRecord() async {
        // status valid but no record (an unusual stored shape) — nothing to
        // validate, so the client is never called.
        let repository = InMemoryLicenseRepository(
            state: LicenseState(status: .valid, record: nil, trial: .initial))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient)

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 0)
    }

    // MARK: - Trial day-of-use

    @Test func recordsOneTrialDayThenNotAgainSameDay() {
        let repository = InMemoryLicenseRepository(state: trialState(daysUsed: 0, lastUsedDate: ""))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient, today: { "2026-07-16" })

        gate.recordTrialUsageOnLaunch()
        #expect(gate.state().trial.daysUsed == 1)
        #expect(repository.savedStates.count == 1)

        // A second launch on the same day does not count again — and does not
        // write again.
        gate.recordTrialUsageOnLaunch()
        #expect(gate.state().trial.daysUsed == 1)
        #expect(repository.savedStates.count == 1)
    }

    @Test func recordsAnotherTrialDayOnTheNextDay() {
        let repository = InMemoryLicenseRepository(
            state: trialState(daysUsed: 1, lastUsedDate: "2026-07-15"))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient, today: { "2026-07-16" })

        gate.recordTrialUsageOnLaunch()

        #expect(gate.state().trial.daysUsed == 2)
    }

    /// Day 30 spends the trial: the status flips to `expired` and the gate
    /// closes.
    @Test func trialExpiresAndClosesTheGateAtDayThirty() {
        let repository = InMemoryLicenseRepository(
            state: trialState(daysUsed: 29, lastUsedDate: "2026-07-15"))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient, today: { "2026-07-16" })

        // Open on the 30th day of use...
        #expect(gate.isOpen())
        gate.recordTrialUsageOnLaunch()

        #expect(gate.state().trial.daysUsed == 30)
        #expect(gate.state().status == .expired)
        #expect(!gate.isOpen())
    }

    @Test func trialRecordingSkipsWhenNotInTrial() {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient)

        gate.recordTrialUsageOnLaunch()

        #expect(gate.state().status == .valid)
        #expect(repository.savedStates.isEmpty)
    }

    // MARK: - Activation

    @Test func activationStoresTheValidRecord() async {
        let repository = InMemoryLicenseRepository(state: .freshTrial)
        let apiClient = StubLicenseApiClient()
        let activated = LicenseRecord(
            licenseKey: "NEW-KEY", activationId: "NEW-ACT",
            validUntil: t1, lastValidated: t0, status: .valid)
        apiClient.activationOutcome = .activated(record: activated)
        let gate = makeGate(repository: repository, apiClient: apiClient)

        let outcome = await gate.activate(key: "NEW-KEY")

        #expect(outcome == .activated(record: activated))
        #expect(apiClient.lastActivateKey == "NEW-KEY")
        #expect(apiClient.lastActivateDevice == device)
        #expect(gate.state().status == .valid)
        #expect(gate.state().record == activated)
        #expect(gate.isOpen())
        #expect(repository.savedStates.last?.record == activated)
    }

    @Test func activationRejectionDowngradesAndPersists() async {
        let repository = InMemoryLicenseRepository(state: .freshTrial)
        let apiClient = StubLicenseApiClient()
        apiClient.activationOutcome = .rejected(.invalidKey)
        let gate = makeGate(repository: repository, apiClient: apiClient)

        let outcome = await gate.activate(key: "BAD-KEY")

        #expect(outcome == .rejected(.invalidKey))
        #expect(gate.state().status == .invalid)
        #expect(!gate.isOpen())
        #expect(repository.savedStates.last?.status == .invalid)
    }

    /// A no-answer activation is retryable: it changes nothing and writes
    /// nothing, leaving the trial intact.
    @Test func activationWithNoResponseLeavesStateUnchanged() async {
        let repository = InMemoryLicenseRepository(state: .freshTrial)
        let apiClient = StubLicenseApiClient()
        apiClient.activationOutcome = .noResponse
        let gate = makeGate(repository: repository, apiClient: apiClient)

        let outcome = await gate.activate(key: "KEY")

        #expect(outcome == .noResponse)
        #expect(gate.state().status == .trial)
        #expect(gate.isOpen())
        #expect(repository.savedStates.isEmpty)
    }

    // MARK: - Lazy load

    @Test func doesNotLoadStateAtConstruction() {
        let repository = InMemoryLicenseRepository(state: validState())
        _ = makeGate(repository: repository, apiClient: StubLicenseApiClient())

        #expect(repository.loadCount == 0)
    }

    @Test func loadsStateOnceThenHoldsItInMemory() {
        let repository = InMemoryLicenseRepository(state: validState())
        let gate = makeGate(repository: repository, apiClient: StubLicenseApiClient())

        _ = gate.isOpen()
        _ = gate.state()
        _ = gate.isOpen()

        #expect(repository.loadCount == 1)
    }
}
