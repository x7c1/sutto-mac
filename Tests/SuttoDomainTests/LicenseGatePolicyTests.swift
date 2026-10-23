import Foundation
import Testing

@testable import SuttoDomain

/// The gate decision: the authoritative status, the local trial, and the
/// connectivity axis (whether the device is online, and how long since it was
/// last online). These tests pin "valid is open unless offline for 7 days or
/// more since it was last online", "trial is open until day 30, online or
/// offline", and "trial-expired / expired / invalid are closed".
@Suite struct LicenseGatePolicyTests {
    private func isOpen(
        _ status: LicenseStatus,
        trial: TrialState = .initial,
        online: Bool = true,
        daysSinceLastOnline: Double = 0
    ) -> Bool {
        LicenseGatePolicy.isGateOpen(
            status: status, trial: trial, isOnline: online,
            daysSinceLastOnline: daysSinceLastOnline)
    }

    @Test func offlineGracePeriodIsSevenDays() {
        #expect(LicenseGatePolicy.offlineGracePeriodDays == 7)
    }

    // MARK: - valid

    @Test func validIsOpenWhileOnline() {
        #expect(isOpen(.valid, online: true))
    }

    /// Online, the time since the last-online record does not matter.
    @Test func validIsOpenOnlineHoweverLongAgoLastOnlineWasRecorded() {
        #expect(isOpen(.valid, online: true, daysSinceLastOnline: 400))
    }

    /// A valid device stays open even with a fully expired trial: the trial is
    /// irrelevant once a license is valid.
    @Test func validIsOpenEvenWhenTheTrialWouldBeExpired() {
        let exhausted = TrialState(daysUsed: TrialState.maxDays, lastUsedDate: "2026-07-16")
        #expect(isOpen(.valid, trial: exhausted))
    }

    @Test func validIsOpenOfflineWithinSevenDaysOfLastOnline() {
        #expect(isOpen(.valid, online: false, daysSinceLastOnline: 6))
        #expect(isOpen(.valid, online: false, daysSinceLastOnline: 6.99))
    }

    /// The 7-day boundary: closed once 7 full days have passed since the
    /// device was last online.
    @Test func validIsClosedOfflineAtSevenOrMoreDaysSinceLastOnline() {
        #expect(!isOpen(.valid, online: false, daysSinceLastOnline: 7))
        #expect(!isOpen(.valid, online: false, daysSinceLastOnline: 30))
    }

    @Test func offlineGraceIsExceededOnlyOfflineAtSevenDaysOrMore() {
        #expect(!LicenseGatePolicy.isOfflineGraceExceeded(isOnline: true, daysSinceLastOnline: 30))
        #expect(!LicenseGatePolicy.isOfflineGraceExceeded(isOnline: false, daysSinceLastOnline: 6))
        #expect(LicenseGatePolicy.isOfflineGraceExceeded(isOnline: false, daysSinceLastOnline: 7))
    }

    // MARK: - trial

    @Test func trialIsOpenWithDaysRemaining() {
        let trial = TrialState(daysUsed: 5, lastUsedDate: "2026-07-16")
        #expect(isOpen(.trial, trial: trial))
    }

    /// The trial is fully local: it stays open however long the device has
    /// been offline.
    @Test func trialIsOpenOfflineRegardlessOfLastOnline() {
        let trial = TrialState(daysUsed: 5, lastUsedDate: "2026-07-16")
        #expect(isOpen(.trial, trial: trial, online: false, daysSinceLastOnline: 30))
    }

    /// The 29 → 30 boundary: open on the last day of the trial, closed once the
    /// full length is reached.
    @Test func trialClosesAtTheThirtyDayBoundary() {
        let lastDay = TrialState(daysUsed: 29, lastUsedDate: "2026-07-16")
        #expect(isOpen(.trial, trial: lastDay))

        let expired = TrialState(daysUsed: 30, lastUsedDate: "2026-07-16")
        #expect(!isOpen(.trial, trial: expired))
    }

    // MARK: - closed statuses

    /// A spent trial is closed regardless of the stored trial counter — the
    /// status alone decides.
    @Test func trialExpiredIsClosed() {
        #expect(LicenseStatus.trialExpired.rawValue == "trial-expired")
        let spent = TrialState(daysUsed: TrialState.maxDays, lastUsedDate: "2026-07-16")
        #expect(!isOpen(.trialExpired, trial: spent))
        #expect(!isOpen(.trialExpired, trial: .initial))
    }

    /// `trialExpired`, `expired`, and `invalid` are closed online and offline,
    /// however recently the device was last online.
    @Test(arguments: [LicenseStatus.trialExpired, .expired, .invalid])
    func closedStatusesStayClosedOnlineOrOffline(status: LicenseStatus) {
        #expect(!isOpen(status, online: true, daysSinceLastOnline: 0))
        #expect(!isOpen(status, online: false, daysSinceLastOnline: 0))
        #expect(!isOpen(status, online: false, daysSinceLastOnline: 30))
    }

    // MARK: - days since last online

    @Test func daysSinceLastOnlineCountsFractionalDays() {
        let lastOnlineAt = Date(timeIntervalSince1970: 1_000_000_000)
        let now = lastOnlineAt.addingTimeInterval(36 * 60 * 60)
        #expect(LicenseGatePolicy.daysSinceLastOnline(lastOnlineAt, now: now) == 1.5)
    }

    /// A last-online time in the future (the clock moved backwards) counts as
    /// zero days, never negative.
    @Test func daysSinceLastOnlineIsNeverNegative() {
        let lastOnlineAt = Date(timeIntervalSince1970: 1_000_000_000)
        let now = lastOnlineAt.addingTimeInterval(-60)
        #expect(LicenseGatePolicy.daysSinceLastOnline(lastOnlineAt, now: now) == 0)
    }
}
