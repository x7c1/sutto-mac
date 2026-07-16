import Foundation
import Testing

@testable import SuttoDomain

/// The local day-of-use trial: it counts one day per distinct calendar day,
/// caps at 30, and never counts the same day twice. The "day" is an injected
/// string, so no clock is involved. Ports the GNOME `TrialDays` +
/// `TrialPeriod` semantics.
@Suite struct TrialStateTests {
    @Test func trialLengthMirrorsTheGnomeConstant() {
        // MAX_DAYS = 30 in the GNOME version's trial-days.ts.
        #expect(TrialState.maxDays == 30)
    }

    @Test func initialIsFresh() {
        #expect(TrialState.initial.daysUsed == 0)
        #expect(TrialState.initial.lastUsedDate == "")
        #expect(!TrialState.initial.isExpired)
        #expect(TrialState.initial.remainingDays == 30)
    }

    @Test func recordingTheFirstDayCountsOne() {
        let trial = TrialState.initial.recordUsage(today: "2026-07-16")
        #expect(trial.daysUsed == 1)
        #expect(trial.lastUsedDate == "2026-07-16")
        #expect(trial.remainingDays == 29)
    }

    /// Same day twice: the second call is not countable and returns the
    /// unchanged state.
    @Test func sameDayIsNotCountedTwice() {
        let today = "2026-07-16"
        let afterFirst = TrialState.initial.recordUsage(today: today)

        #expect(!afterFirst.canRecordUsage(today: today))

        let afterSecond = afterFirst.recordUsage(today: today)
        #expect(afterSecond == afterFirst)
        #expect(afterSecond.daysUsed == 1)
    }

    @Test func aNewDayIsCountable() {
        let afterFirst = TrialState.initial.recordUsage(today: "2026-07-16")

        #expect(afterFirst.canRecordUsage(today: "2026-07-17"))

        let afterSecond = afterFirst.recordUsage(today: "2026-07-17")
        #expect(afterSecond.daysUsed == 2)
        #expect(afterSecond.lastUsedDate == "2026-07-17")
    }

    /// The 29 → 30 expiry boundary: day 30 is the last countable day, after
    /// which the trial is expired and no longer countable.
    @Test func recordingTheLastDayExpiresTheTrial() {
        let dayBefore = TrialState(daysUsed: 29, lastUsedDate: "2026-07-15")
        #expect(!dayBefore.isExpired)
        #expect(dayBefore.canRecordUsage(today: "2026-07-16"))

        let expired = dayBefore.recordUsage(today: "2026-07-16")
        #expect(expired.daysUsed == 30)
        #expect(expired.isExpired)
    }

    /// An expired trial is not countable on any day, and recording caps at 30.
    @Test func recordingIsCappedAtThirtyAndBlockedWhenExpired() {
        let expired = TrialState(daysUsed: 30, lastUsedDate: "2026-07-16")
        #expect(expired.isExpired)
        #expect(!expired.canRecordUsage(today: "2026-08-01"))

        let unchanged = expired.recordUsage(today: "2026-08-01")
        #expect(unchanged.daysUsed == 30)
        #expect(unchanged == expired)
    }

    /// A stored count outside 0...30 self-heals on load rather than being
    /// rejected — corrupt storage must not fabricate a worse verdict
    /// (design decision #8).
    @Test func daysUsedIsClampedIntoRange() {
        #expect(TrialState(daysUsed: -5, lastUsedDate: "").daysUsed == 0)
        #expect(TrialState(daysUsed: 999, lastUsedDate: "").daysUsed == 30)
    }
}
