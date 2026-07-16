import Foundation
import Testing

@testable import SuttoDomain

/// The gate decision under the unlimited fail-open policy: it reads only the
/// authoritative status and the local trial, never staleness or network state
/// (design decisions #1 and #6). These tests pin "valid is always open",
/// "trial is open until day 30", and "expired / invalid are closed".
@Suite struct LicenseGatePolicyTests {
    @Test func validIsOpenUnconditionally() {
        #expect(LicenseGatePolicy.isGateOpen(status: .valid, trial: .initial))
    }

    /// A valid device stays open even with a fully expired trial: the trial is
    /// irrelevant once a license is valid.
    @Test func validIsOpenEvenWhenTheTrialWouldBeExpired() {
        let exhausted = TrialState(daysUsed: TrialState.maxDays, lastUsedDate: "2026-07-16")
        #expect(LicenseGatePolicy.isGateOpen(status: .valid, trial: exhausted))
    }

    @Test func trialIsOpenWithDaysRemaining() {
        let trial = TrialState(daysUsed: 5, lastUsedDate: "2026-07-16")
        #expect(LicenseGatePolicy.isGateOpen(status: .trial, trial: trial))
    }

    /// The 29 → 30 boundary: open on the last day of the trial, closed once the
    /// full length is reached.
    @Test func trialClosesAtTheThirtyDayBoundary() {
        let lastDay = TrialState(daysUsed: 29, lastUsedDate: "2026-07-16")
        #expect(LicenseGatePolicy.isGateOpen(status: .trial, trial: lastDay))

        let expired = TrialState(daysUsed: 30, lastUsedDate: "2026-07-16")
        #expect(!LicenseGatePolicy.isGateOpen(status: .trial, trial: expired))
    }

    @Test func expiredIsClosed() {
        #expect(!LicenseGatePolicy.isGateOpen(status: .expired, trial: .initial))
    }

    @Test func invalidIsClosed() {
        #expect(!LicenseGatePolicy.isGateOpen(status: .invalid, trial: .initial))
    }
}
