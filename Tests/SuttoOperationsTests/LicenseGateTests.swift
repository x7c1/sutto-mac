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
        connectivity: StubConnectivity = StubConnectivity(isOnline: true),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) },
        today: @escaping () -> String = { "2026-07-16" }
    ) -> LicenseGate {
        LicenseGate(
            repository: repository, apiClient: apiClient, device: device,
            connectivity: connectivity, now: now, today: today)
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
            trial: .initial,
            lastOnlineAt: t0
        )
    }

    private func trialState(daysUsed: Int, lastUsedDate: String) -> LicenseState {
        LicenseState(
            status: .trial, record: nil,
            trial: TrialState(daysUsed: daysUsed, lastUsedDate: lastUsedDate), lastOnlineAt: t0)
    }

    // MARK: - Fail-open: no authoritative answer never downgrades

    /// The most important case: a valid device whose launch validate gets no
    /// authoritative answer stays open, keeps `valid`, and writes nothing but
    /// the last-online time.
    @Test func validDeviceStaysOpenWhenValidateHasNoResponse() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .noResponse
        let gate = makeGate(repository: repository, apiClient: apiClient)

        await gate.validateOnLaunch()

        #expect(gate.isOpen())
        #expect(gate.state().status == .valid)
        // Fail-open leaves the cached status and record alone; the only write
        // is the last-online time recorded before the validate.
        #expect(repository.savedStates.count == 1)
        #expect(repository.savedStates.first?.status == .valid)
        #expect(repository.savedStates.first?.record == validState().record)
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
            state: LicenseState(status: .valid, record: nil, trial: .initial, lastOnlineAt: t0))
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

        gate.recordTrialUsage()
        #expect(gate.state().trial.daysUsed == 1)
        #expect(repository.savedStates.count == 1)

        // A second show on the same day does not count again — and does not
        // write again.
        gate.recordTrialUsage()
        #expect(gate.state().trial.daysUsed == 1)
        #expect(repository.savedStates.count == 1)
    }

    @Test func recordsAnotherTrialDayOnTheNextDay() {
        let repository = InMemoryLicenseRepository(
            state: trialState(daysUsed: 1, lastUsedDate: "2026-07-15"))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient, today: { "2026-07-16" })

        gate.recordTrialUsage()

        #expect(gate.state().trial.daysUsed == 2)
    }

    /// Day 30 spends the trial: the status flips to `trialExpired` — never the
    /// backend's `expired` — and the gate closes.
    @Test func trialBecomesTrialExpiredAndClosesTheGateAtDayThirty() {
        let repository = InMemoryLicenseRepository(
            state: trialState(daysUsed: 29, lastUsedDate: "2026-07-15"))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient, today: { "2026-07-16" })

        // Open on the 30th day of use...
        #expect(gate.isOpen())
        gate.recordTrialUsage()

        #expect(gate.state().trial.daysUsed == 30)
        #expect(gate.state().status == .trialExpired)
        #expect(repository.savedStates.last?.status == .trialExpired)
        #expect(!gate.isOpen())
    }

    /// Counting is purely local: it does not consult the backend at all.
    @Test func trialRecordingNeverTouchesTheBackend() {
        let repository = InMemoryLicenseRepository(
            state: trialState(daysUsed: 3, lastUsedDate: "2026-07-15"))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient, today: { "2026-07-16" })

        gate.recordTrialUsage()

        #expect(gate.state().trial.daysUsed == 4)
        #expect(apiClient.validateCount == 0)
    }

    @Test(arguments: [LicenseStatus.trialExpired, .valid, .expired, .invalid])
    func trialRecordingSkipsWhenNotInTrial(status: LicenseStatus) {
        let state = LicenseState(
            status: status,
            record: status == .trialExpired ? nil : validState(status: status).record,
            trial: TrialState(daysUsed: 10, lastUsedDate: "2026-07-15"), lastOnlineAt: t0)
        let repository = InMemoryLicenseRepository(state: state)
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient, today: { "2026-07-16" })

        gate.recordTrialUsage()

        #expect(gate.state() == state)
        #expect(repository.savedStates.isEmpty)
    }

    // MARK: - Activation

    @Test func activationStoresTheValidRecord() async {
        let repository = InMemoryLicenseRepository(state: .freshTrial(now: t0))
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

    /// The key regression: a rejected activation while in trial must not
    /// destroy the trial. The bad key is reported through the returned
    /// outcome, but the status stays `trial`, the gate stays open, and nothing
    /// is written (diverges from GNOME's `setStatus('invalid')`; design
    /// decision #8).
    @Test func activationRejectionDoesNotDestroyAnInProgressTrial() async {
        let repository = InMemoryLicenseRepository(
            state: trialState(daysUsed: 3, lastUsedDate: "2026-07-15"))
        let apiClient = StubLicenseApiClient()
        apiClient.activationOutcome = .rejected(.invalidKey)
        let gate = makeGate(repository: repository, apiClient: apiClient)

        let outcome = await gate.activate(key: "BAD-KEY")

        #expect(outcome == .rejected(.invalidKey))
        #expect(gate.state().status == .trial)
        #expect(gate.isOpen())
        #expect(repository.savedStates.isEmpty)
    }

    /// A rejected activation on an already-valid device does not downgrade it
    /// either — only `validateOnLaunch` downgrades a valid device.
    @Test func activationRejectionDoesNotDowngradeAValidDevice() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        apiClient.activationOutcome = .rejected(.expired)
        let gate = makeGate(repository: repository, apiClient: apiClient)

        let outcome = await gate.activate(key: "SOME-KEY")

        #expect(outcome == .rejected(.expired))
        #expect(gate.state().status == .valid)
        #expect(gate.isOpen())
        #expect(repository.savedStates.isEmpty)
    }

    /// A no-answer activation is retryable: it changes nothing and writes
    /// nothing, leaving the trial intact.
    @Test func activationWithNoResponseLeavesStateUnchanged() async {
        let repository = InMemoryLicenseRepository(state: .freshTrial(now: t0))
        let apiClient = StubLicenseApiClient()
        apiClient.activationOutcome = .noResponse
        let gate = makeGate(repository: repository, apiClient: apiClient)

        let outcome = await gate.activate(key: "KEY")

        #expect(outcome == .noResponse)
        #expect(gate.state().status == .trial)
        #expect(gate.isOpen())
        #expect(repository.savedStates.isEmpty)
    }

    // MARK: - Clear license (local Deactivate)

    /// Clearing a valid license mid-trial drops the record and returns to the
    /// trial with the days already used preserved — the gate stays open.
    @Test func clearReturnsToTrialWhenTrialNotExpired() {
        let repository = InMemoryLicenseRepository(
            state: LicenseState(
                status: .valid,
                record: LicenseRecord(
                    licenseKey: "KEY-123", activationId: "ACT-456",
                    validUntil: t0, lastValidated: t0, status: .valid),
                trial: TrialState(daysUsed: 5, lastUsedDate: "2026-07-10"), lastOnlineAt: t0))
        let gate = makeGate(repository: repository, apiClient: StubLicenseApiClient())

        gate.clearLicense()

        #expect(gate.state().status == .trial)
        #expect(gate.state().record == nil)
        #expect(gate.state().trial.daysUsed == 5)
        #expect(gate.isOpen())
        #expect(repository.savedStates.last?.status == .trial)
        #expect(repository.savedStates.last?.record == nil)
    }

    /// Clearing when the trial is already spent lands on `trialExpired`, not a
    /// fresh trial — clearing must not hand back a trial the device no longer
    /// has — and not `expired`, which only the backend may produce.
    @Test func clearBecomesTrialExpiredWhenTrialIsSpent() {
        let repository = InMemoryLicenseRepository(
            state: LicenseState(
                status: .valid,
                record: LicenseRecord(
                    licenseKey: "KEY-123", activationId: "ACT-456",
                    validUntil: t0, lastValidated: t0, status: .valid),
                trial: TrialState(daysUsed: 30, lastUsedDate: "2026-07-10"), lastOnlineAt: t0))
        let gate = makeGate(repository: repository, apiClient: StubLicenseApiClient())

        gate.clearLicense()

        #expect(gate.state().status == .trialExpired)
        #expect(gate.state().record == nil)
        #expect(!gate.isOpen())
        #expect(repository.savedStates.last?.status == .trialExpired)
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

    // MARK: - Connectivity: the last-online time and the launch validate

    /// Online at launch: the last-online time is recorded before the validate,
    /// and the validate is attempted.
    @Test func launchOnlineRecordsLastOnlineAndValidates() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(
            repository: repository, apiClient: apiClient,
            connectivity: StubConnectivity(isOnline: true), now: { self.t1 })

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 1)
        #expect(gate.state().lastOnlineAt == t1)
        #expect(repository.storedState.lastOnlineAt == t1)
    }

    /// Offline at launch: no validate is attempted (offline is not "no
    /// answer"), and neither the status nor the last-online time changes.
    @Test func launchOfflineSkipsTheValidateAndLeavesTheStateUnchanged() async {
        let state = validState()
        let repository = InMemoryLicenseRepository(state: state)
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .rejected(.expired)
        let gate = makeGate(
            repository: repository, apiClient: apiClient,
            connectivity: StubConnectivity(isOnline: false), now: { self.t1 })

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 0)
        #expect(gate.state() == state)
        #expect(gate.state().lastOnlineAt == t0)
        #expect(repository.savedStates.isEmpty)
    }

    /// Online at launch, a trial records the last-online time too; there is
    /// nothing to validate.
    @Test func launchOnlineRecordsLastOnlineForATrial() async {
        let repository = InMemoryLicenseRepository(
            state: trialState(daysUsed: 3, lastUsedDate: "2026-07-15"))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { self.t1 })

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 0)
        #expect(gate.state().lastOnlineAt == t1)
    }

    /// A panel show during the launch validate records a newer last-online
    /// time; the validate's answer is applied on top of it, never over it with
    /// the state read before the request.
    @Test func launchValidateKeepsALastOnlineRecordedWhileItWaited() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .valid(validUntil: t1)
        var now = t1
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { now })
        let later = t1.addingTimeInterval(60)
        apiClient.duringValidate = {
            now = later
            _ = gate.admitsPanelShow()
        }

        await gate.validateOnLaunch()

        #expect(gate.state().lastOnlineAt == later)
        #expect(gate.state().record?.lastValidated == later)
        #expect(repository.storedState.lastOnlineAt == later)
    }

    /// A license cleared while the launch validate waited is not downgraded by
    /// that validate's answer: the answer was about a license no longer stored.
    @Test func launchValidateIgnoresItsAnswerWhenTheLicenseWasClearedMeanwhile() async {
        let repository = InMemoryLicenseRepository(state: validState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .rejected(.expired)
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { self.t1 })
        apiClient.duringValidate = { gate.clearLicense() }

        await gate.validateOnLaunch()

        #expect(gate.state().status == .trial)
        #expect(gate.state().record == nil)
        #expect(repository.storedState.status == .trial)
    }

    /// Each panel-show attempt records the last-online time while online, and
    /// leaves it alone while offline.
    @Test func panelShowAttemptRecordsLastOnlineOnlyWhileOnline() {
        let connectivity = StubConnectivity(isOnline: false)
        var now = t1
        let repository = InMemoryLicenseRepository(state: validState())
        let gate = makeGate(
            repository: repository, apiClient: StubLicenseApiClient(),
            connectivity: connectivity, now: { now })

        #expect(gate.admitsPanelShow())
        #expect(gate.state().lastOnlineAt == t0)
        #expect(repository.savedStates.isEmpty)

        connectivity.set(isOnline: true)
        now = t1.addingTimeInterval(60)
        #expect(gate.admitsPanelShow())
        #expect(gate.state().lastOnlineAt == now)
        #expect(repository.storedState.lastOnlineAt == now)
    }

    /// Every connectivity change into or out of online records the last-online
    /// time — the device was online until it dropped — and calls back.
    @Test func connectivityChangesRecordLastOnlineIntoAndOutOfOnline() {
        let connectivity = StubConnectivity(isOnline: false)
        var now = t1
        let repository = InMemoryLicenseRepository(state: validState())
        let gate = makeGate(
            repository: repository, apiClient: StubLicenseApiClient(),
            connectivity: connectivity, now: { now })
        var changes = 0
        gate.watchConnectivity { changes += 1 }

        // Offline → online.
        connectivity.report(isOnline: true)
        #expect(gate.state().lastOnlineAt == t1)

        // Online → offline: the device was online until now.
        now = t1.addingTimeInterval(3600)
        connectivity.report(isOnline: false)
        #expect(gate.state().lastOnlineAt == now)
        #expect(repository.storedState.lastOnlineAt == now)

        // Offline → offline: nothing was online, so nothing is recorded.
        let lastRecorded = now
        now = t1.addingTimeInterval(7200)
        connectivity.report(isOnline: false)
        #expect(gate.state().lastOnlineAt == lastRecorded)

        #expect(changes == 3)
    }

    // MARK: - Trial probe: a spent trial asks whether the license server is there

    private func spentTrialState(
        trialProbe: TrialProbeResult = .none, lastOnlineAt: Date? = nil
    ) -> LicenseState {
        LicenseState(
            status: .trialExpired, record: nil,
            trial: TrialState(daysUsed: TrialState.maxDays, lastUsedDate: "2026-07-15"),
            lastOnlineAt: lastOnlineAt ?? t0, trialProbeResult: trialProbe)
    }

    private static let day: TimeInterval = 24 * 60 * 60

    /// Online, the server answers (here by refusing the empty key): the result
    /// is `answered`, the status stays `trialExpired`, and the gate stays
    /// closed. The probe is a validate with an empty key and activation id.
    @Test func trialProbeAnsweredKeepsTheSpentTrialClosed() async {
        let repository = InMemoryLicenseRepository(state: spentTrialState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .rejected(.invalidKey)
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { self.t1 })

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 1)
        #expect(apiClient.lastValidateKey == "")
        #expect(apiClient.lastValidateActivationId == "")
        #expect(gate.state().trialProbeResult == .answered)
        #expect(gate.state().status == .trialExpired)
        #expect(repository.storedState.trialProbeResult == .answered)
        #expect(!gate.isOpen())
        #expect(!gate.admitsPanelShow())
    }

    /// A server that accepts the probe has answered too.
    @Test func trialProbeAcceptedCountsAsAnswered() async {
        let repository = InMemoryLicenseRepository(state: spentTrialState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .valid(validUntil: t1)
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { self.t1 })

        await gate.validateOnLaunch()

        #expect(gate.state().trialProbeResult == .answered)
        #expect(gate.state().status == .trialExpired)
        #expect(gate.state().record == nil)
        #expect(!gate.isOpen())
    }

    /// Online, the server does not answer: the result is `noResponse`, the
    /// status stays `trialExpired`, and the gate opens.
    @Test func trialProbeNoResponseOpensTheSpentTrial() async {
        let repository = InMemoryLicenseRepository(state: spentTrialState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .noResponse
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { self.t1 })

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 1)
        #expect(gate.state().trialProbeResult == .noResponse)
        #expect(gate.state().status == .trialExpired)
        #expect(repository.storedState.trialProbeResult == .noResponse)
        #expect(gate.isOpen())
        #expect(gate.admitsPanelShow())
    }

    /// Offline at launch, the probe is not attempted and the stored result is
    /// kept, whichever it is.
    @Test(arguments: [TrialProbeResult.none, .answered, .noResponse])
    func trialProbeIsSkippedOfflineAndKeepsTheStoredResult(
        trialProbe: TrialProbeResult
    ) async {
        let state = spentTrialState(trialProbe: trialProbe)
        let repository = InMemoryLicenseRepository(state: state)
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .rejected(.invalidKey)
        let gate = makeGate(
            repository: repository, apiClient: apiClient,
            connectivity: StubConnectivity(isOnline: false), now: { self.t1 })

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 0)
        #expect(gate.state() == state)
        #expect(repository.savedStates.isEmpty)
    }

    /// A spent trial opened by an unanswered probe follows the `valid` offline
    /// rule: open offline under 7 days since last online, closed at 7 or more.
    @Test(arguments: [(0.0, true), (6.0, true), (6.99, true), (7.0, false), (30.0, false)])
    func trialProbeNoResponseFollowsTheOfflineLimit(
        daysSinceLastOnline: Double, expectedOpen: Bool
    ) async {
        let now = t0.addingTimeInterval(daysSinceLastOnline * Self.day)
        let repository = InMemoryLicenseRepository(
            state: spentTrialState(trialProbe: .noResponse, lastOnlineAt: t0))
        let apiClient = StubLicenseApiClient()
        let gate = makeGate(
            repository: repository, apiClient: apiClient,
            connectivity: StubConnectivity(isOnline: false), now: { now })

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 0)
        #expect(gate.state().trialProbeResult == .noResponse)
        #expect(gate.isOpen() == expectedOpen)
        #expect(gate.admitsPanelShow() == expectedOpen)
    }

    /// A device that found the server gone, back online with the server
    /// answering again, is closed again.
    @Test func trialProbeAnsweredAgainClosesAPreviouslyOpenSpentTrial() async {
        let repository = InMemoryLicenseRepository(
            state: spentTrialState(trialProbe: .noResponse))
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .rejected(.invalidKey)
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { self.t1 })
        #expect(gate.isOpen())

        await gate.validateOnLaunch()

        #expect(gate.state().trialProbeResult == .answered)
        #expect(repository.storedState.trialProbeResult == .answered)
        #expect(!gate.isOpen())
    }

    /// Only a spent trial is probed: `trial`, `valid`, `expired`, and
    /// `invalid` never send the empty-key validate, and never change the
    /// stored probe result.
    @Test(arguments: [LicenseStatus.trial, .valid, .expired, .invalid])
    func trialProbeIsNeverSentForOtherStatuses(status: LicenseStatus) async {
        let state =
            status == .trial ? trialState(daysUsed: 3, lastUsedDate: "2026-07-15")
            : validState(status: status)
        let repository = InMemoryLicenseRepository(state: state)
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .noResponse
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { self.t1 })

        await gate.validateOnLaunch()

        #expect(apiClient.lastValidateKey != "")
        #expect(gate.state().trialProbeResult == .none)
        #expect(gate.state().status == status)
        if status != .valid {
            #expect(apiClient.validateCount == 0)
        }
    }

    /// A license activated while the probe waited is not overwritten by the
    /// probe's answer: the stored state stays `valid` with its record, and no
    /// probe result is written over it.
    @Test func trialProbeInFlightDoesNotOverwriteAnActivation() async {
        let repository = InMemoryLicenseRepository(state: spentTrialState())
        let apiClient = StubLicenseApiClient()
        apiClient.validationOutcome = .noResponse
        let record = LicenseRecord(
            licenseKey: "KEY-NEW", activationId: "ACT-NEW", validUntil: t1, lastValidated: t1,
            status: .valid)
        apiClient.activationOutcome = .activated(record: record)
        let gate = makeGate(repository: repository, apiClient: apiClient, now: { self.t1 })
        apiClient.duringValidateAsync = { _ = await gate.activate(key: "KEY-NEW") }

        await gate.validateOnLaunch()

        #expect(apiClient.validateCount == 1)
        #expect(apiClient.activateCount == 1)
        #expect(gate.state().status == .valid)
        #expect(gate.state().record == record)
        #expect(gate.state().trialProbeResult == .none)
        #expect(repository.storedState.status == .valid)
        #expect(repository.storedState.record == record)
        #expect(repository.storedState.trialProbeResult == .none)
        #expect(gate.isOpen())
    }
}
