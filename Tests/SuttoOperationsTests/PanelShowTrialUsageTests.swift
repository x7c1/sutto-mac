import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

/// "Show the panel" across every licensing state: a ``PanelToggleUseCase``
/// wired to a real ``LicenseGate`` exactly as the composition root wires it
/// (`isGateOpen` → ``LicenseGate/isOpen()``, `onPanelShown` →
/// ``LicenseGate/recordTrialUsage()``), pinning whether a trial day is counted
/// and whether the panel is shown.
@Suite @MainActor struct PanelShowTrialUsageTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let today = "2026-07-16"
    private static let yesterday = "2026-07-15"

    /// The panel and gate wired together, plus the counters the tests read.
    @MainActor private final class Fixture {
        let repository: InMemoryLicenseRepository
        let gate: LicenseGate
        var useCase: PanelToggleUseCase!
        var visible = false
        private(set) var shownCount = 0
        private(set) var refusedCount = 0

        init(state: LicenseState, today: String) {
            repository = InMemoryLicenseRepository(state: state)
            gate = LicenseGate(
                repository: repository,
                apiClient: StubLicenseApiClient(),
                device: DeviceIdentity(id: "device-1", label: "Test Mac"),
                today: { today })
        }

        func recordShow() { shownCount += 1 }
        func recordRefusal() { refusedCount += 1 }

        /// Toggles from the hidden state, so every call is a show attempt.
        func show() {
            visible = false
            useCase.toggle()
        }
    }

    private func makeFixture(_ state: LicenseState) -> Fixture {
        let fixture = Fixture(state: state, today: Self.today)
        fixture.useCase = PanelToggleUseCase(
            isPanelVisible: { [unowned fixture] in fixture.visible },
            showPanel: { [unowned fixture] in
                fixture.visible = true
                fixture.recordShow()
            },
            hidePanel: { [unowned fixture] in fixture.visible = false },
            isGateOpen: { [unowned fixture] in fixture.gate.isOpen() },
            onGateClosed: { [unowned fixture] in fixture.recordRefusal() },
            onPanelShown: { [unowned fixture] in fixture.gate.recordTrialUsage() }
        )
        return fixture
    }

    private func trial(daysUsed: Int, lastUsedDate: String) -> LicenseState {
        LicenseState(
            status: .trial, record: nil,
            trial: TrialState(daysUsed: daysUsed, lastUsedDate: lastUsedDate))
    }

    private func record(status: LicenseStatus) -> LicenseRecord {
        LicenseRecord(
            licenseKey: "KEY-123", activationId: "ACT-456",
            validUntil: t0, lastValidated: t0, status: status)
    }

    @Test func trialNotYetCountedTodayCountsADayAndShows() {
        let f = makeFixture(trial(daysUsed: 3, lastUsedDate: Self.yesterday))

        f.show()

        #expect(f.shownCount == 1)
        #expect(f.gate.state().trial.daysUsed == 4)
        #expect(f.gate.state().trial.lastUsedDate == Self.today)
        #expect(f.gate.state().status == .trial)
    }

    @Test func trialAlreadyCountedTodayShowsWithoutCounting() {
        let f = makeFixture(trial(daysUsed: 4, lastUsedDate: Self.today))

        f.show()
        f.show()

        #expect(f.shownCount == 2)
        #expect(f.gate.state().trial.daysUsed == 4)
        #expect(f.repository.savedStates.isEmpty)
    }

    /// The show that records day 30 still shows the panel and turns the status
    /// into `trialExpired`; the next show is refused and not counted.
    @Test func trialAtDayTwentyNineShowsThenBecomesTrialExpired() {
        let f = makeFixture(trial(daysUsed: 29, lastUsedDate: Self.yesterday))

        f.show()

        #expect(f.shownCount == 1)
        #expect(f.gate.state().trial.daysUsed == 30)
        #expect(f.gate.state().status == .trialExpired)
        let savesAfterDayThirty = f.repository.savedStates.count

        f.show()

        #expect(f.shownCount == 1)
        #expect(f.refusedCount == 1)
        #expect(f.gate.state().trial.daysUsed == 30)
        #expect(f.repository.savedStates.count == savesAfterDayThirty)
    }

    /// The gate is open for `valid` only; in every non-trial state no day is
    /// counted, whether the panel is shown or refused.
    @Test(arguments: [
        (LicenseStatus.trialExpired, false),
        (.valid, true),
        (.expired, false),
        (.invalid, false),
    ])
    func nonTrialStatusesNeverCount(status: LicenseStatus, opensPanel: Bool) {
        let state = LicenseState(
            status: status,
            record: status == .trialExpired ? nil : record(status: status),
            trial: TrialState(daysUsed: 10, lastUsedDate: Self.yesterday))
        let f = makeFixture(state)

        f.show()

        #expect(f.shownCount == (opensPanel ? 1 : 0))
        #expect(f.refusedCount == (opensPanel ? 0 : 1))
        #expect(f.gate.state() == state)
        #expect(f.repository.savedStates.isEmpty)
    }

    /// A closed gate refuses the show and counts nothing — even for a `trial`
    /// whose counter is already spent.
    @Test func closedGateNeitherShowsNorCounts() {
        let f = makeFixture(trial(daysUsed: 30, lastUsedDate: Self.yesterday))

        f.show()

        #expect(f.shownCount == 0)
        #expect(f.refusedCount == 1)
        #expect(f.gate.state().trial.daysUsed == 30)
        #expect(f.gate.state().trial.lastUsedDate == Self.yesterday)
        #expect(f.repository.savedStates.isEmpty)
    }
}
