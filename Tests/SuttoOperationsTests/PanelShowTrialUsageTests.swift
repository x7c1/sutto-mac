import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

/// "Show the panel" across every licensing state: a ``PanelToggleUseCase``
/// wired to a real ``LicenseGate`` exactly as the composition root wires it
/// (`isGateOpen` → ``LicenseGate/admitsPanelShow()``, `onPanelShown` →
/// ``LicenseGate/recordTrialUsage()``), pinning whether a trial day is counted,
/// whether the last-online time is recorded, and whether the panel is shown —
/// including the 7-day offline limit and reopening on reconnect.
@Suite @MainActor struct PanelShowTrialUsageTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let today = "2026-07-16"
    private static let yesterday = "2026-07-15"

    /// The panel and gate wired together, plus the counters the tests read.
    @MainActor private final class Fixture {
        let repository: InMemoryLicenseRepository
        let connectivity: StubConnectivity
        let gate: LicenseGate
        /// The gate's clock; tests advance it to age the last-online time.
        var now: Date
        var useCase: PanelToggleUseCase!
        var visible = false
        private(set) var shownCount = 0
        private(set) var refusedCount = 0

        init(state: LicenseState, today: String, isOnline: Bool, now: Date) {
            repository = InMemoryLicenseRepository(state: state)
            connectivity = StubConnectivity(isOnline: isOnline)
            self.now = now
            var clock: (() -> Date)!
            gate = LicenseGate(
                repository: repository,
                apiClient: StubLicenseApiClient(),
                device: DeviceIdentity(id: "device-1", label: "Test Mac"),
                connectivity: connectivity,
                now: { clock() },
                today: { today })
            clock = { [unowned self] in self.now }
        }

        func recordShow() { shownCount += 1 }
        func recordRefusal() { refusedCount += 1 }

        /// Toggles from the hidden state, so every call is a show attempt.
        func show() {
            visible = false
            useCase.toggle()
        }
    }

    /// The trial-day tests run offline with the last-online time at `t0`
    /// (also the clock), so recording the last-online time writes nothing and
    /// the trial counting is observed on its own.
    private func makeFixture(
        _ state: LicenseState, isOnline: Bool = false, now: Date? = nil
    ) -> Fixture {
        let fixture = Fixture(
            state: state, today: Self.today, isOnline: isOnline, now: now ?? t0)
        fixture.useCase = PanelToggleUseCase(
            isPanelVisible: { [unowned fixture] in fixture.visible },
            showPanel: { [unowned fixture] in
                fixture.visible = true
                fixture.recordShow()
            },
            hidePanel: { [unowned fixture] in fixture.visible = false },
            isGateOpen: { [unowned fixture] in fixture.gate.admitsPanelShow() },
            onGateClosed: { [unowned fixture] in fixture.recordRefusal() },
            onPanelShown: { [unowned fixture] in fixture.gate.recordTrialUsage() }
        )
        return fixture
    }

    private func trial(daysUsed: Int, lastUsedDate: String) -> LicenseState {
        LicenseState(
            status: .trial, record: nil,
            trial: TrialState(daysUsed: daysUsed, lastUsedDate: lastUsedDate), lastOnlineAt: t0)
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
            trial: TrialState(daysUsed: 10, lastUsedDate: Self.yesterday), lastOnlineAt: t0)
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

    // MARK: - Offline limit

    private static let day: TimeInterval = 24 * 60 * 60

    private func valid(lastOnlineAt: Date) -> LicenseState {
        LicenseState(
            status: .valid, record: record(status: .valid),
            trial: .initial, lastOnlineAt: lastOnlineAt)
    }

    private static let offlineText =
        "Offline for too long — reconnect to the internet to keep using Sutto"

    /// Online: the panel shows, and the attempt records now as the last-online
    /// time.
    @Test func validOnlineShowsAndUpdatesLastOnline() {
        let now = t0.addingTimeInterval(30 * Self.day)
        let f = makeFixture(valid(lastOnlineAt: t0), isOnline: true, now: now)

        f.show()

        #expect(f.shownCount == 1)
        #expect(f.gate.state().lastOnlineAt == now)
        #expect(f.repository.storedState.lastOnlineAt == now)
    }

    @Test func validOfflineSixDaysAfterLastOnlineShows() {
        let f = makeFixture(
            valid(lastOnlineAt: t0), isOnline: false, now: t0.addingTimeInterval(6 * Self.day))

        f.show()

        #expect(f.shownCount == 1)
        #expect(f.gate.state().lastOnlineAt == t0)
        #expect(f.gate.statusText() != Self.offlineText)
    }

    @Test(arguments: [7.0, 7.5, 30.0])
    func validOfflineSevenOrMoreDaysAfterLastOnlineIsRefused(days: Double) {
        let f = makeFixture(
            valid(lastOnlineAt: t0), isOnline: false,
            now: t0.addingTimeInterval(days * Self.day))

        f.show()

        #expect(f.shownCount == 0)
        #expect(f.refusedCount == 1)
        #expect(f.gate.statusText() == Self.offlineText)
        #expect(f.gate.state().lastOnlineAt == t0)
    }

    /// Offline for 8 days the show is refused; once connectivity reports
    /// online, the next show opens — no relaunch — and the watcher's callback
    /// (which refreshes Settings in the app) has fired.
    @Test func validOfflineEightDaysReopensOnReconnectWithoutRelaunch() {
        let f = makeFixture(
            valid(lastOnlineAt: t0), isOnline: false, now: t0.addingTimeInterval(8 * Self.day))
        var refreshes = 0
        f.gate.watchConnectivity { refreshes += 1 }

        f.show()
        #expect(f.shownCount == 0)
        #expect(f.refusedCount == 1)

        f.now = t0.addingTimeInterval(8 * Self.day + 60)
        f.connectivity.report(isOnline: true)

        #expect(refreshes == 1)
        #expect(f.gate.state().lastOnlineAt == f.now)
        #expect(f.gate.statusText() != Self.offlineText)

        f.show()
        #expect(f.shownCount == 1)
        #expect(f.refusedCount == 1)
    }

    /// The trial is fully local: offline for 30 days it still shows.
    @Test func trialOfflineThirtyDaysShows() {
        let state = LicenseState(
            status: .trial, record: nil,
            trial: TrialState(daysUsed: 3, lastUsedDate: Self.yesterday), lastOnlineAt: t0)
        let f = makeFixture(state, isOnline: false, now: t0.addingTimeInterval(30 * Self.day))

        f.show()

        #expect(f.shownCount == 1)
        #expect(f.gate.state().trial.daysUsed == 4)
        #expect(f.gate.state().lastOnlineAt == t0)
    }

    /// `trialExpired`, `expired`, and `invalid` stay closed whether online or
    /// offline, even right after being online.
    @Test(arguments: [
        (LicenseStatus.trialExpired, true),
        (.trialExpired, false),
        (.expired, true),
        (.expired, false),
        (.invalid, true),
        (.invalid, false),
    ])
    func closedStatusesStayClosedOnlineOrOffline(status: LicenseStatus, isOnline: Bool) {
        let state = LicenseState(
            status: status,
            record: status == .trialExpired ? nil : record(status: status),
            trial: TrialState(daysUsed: 30, lastUsedDate: Self.yesterday), lastOnlineAt: t0)
        let f = makeFixture(state, isOnline: isOnline, now: t0.addingTimeInterval(60))

        f.show()

        #expect(f.shownCount == 0)
        #expect(f.refusedCount == 1)
        #expect(f.gate.statusText() != Self.offlineText)
    }

    /// A stored file without `lastOnlineAt` loads with the load time (see the
    /// file repository); the gate is then decided as if just online, so a
    /// `valid` device shows even while offline.
    @Test func stateLoadedWithoutLastOnlineIsDecidedAsIfJustOnline() {
        let loadTime = t0.addingTimeInterval(100 * Self.day)
        let f = makeFixture(valid(lastOnlineAt: loadTime), isOnline: false, now: loadTime)

        f.show()

        #expect(f.shownCount == 1)
        #expect(f.gate.statusText() != Self.offlineText)
    }
}
