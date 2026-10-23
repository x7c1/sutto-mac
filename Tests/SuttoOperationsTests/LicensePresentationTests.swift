import Foundation
import SuttoDomain
import Testing

@testable import SuttoOperations

/// The pure status/feedback wording of ``LicensePresentation``: the strings the
/// License settings pane and the status-menu row both show. Pinned here (rather
/// than in an AppKit view) so the wording is provable without a window.
@Suite struct LicensePresentationTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(lastValidated: Date) -> LicenseRecord {
        LicenseRecord(
            licenseKey: "KEY", activationId: "ACT",
            validUntil: now, lastValidated: lastValidated, status: .valid)
    }

    // MARK: - Status text

    @Test func trialShowsRemainingDaysPluralized() {
        let state = LicenseState(
            status: .trial, record: nil, trial: TrialState(daysUsed: 5, lastUsedDate: "2026-07-10"), lastOnlineAt: now)
        #expect(
            LicensePresentation.statusText(for: state, isOnline: true, now: now) == "Trial — 25 days remaining")
    }

    @Test func trialShowsSingularDayAtOneRemaining() {
        let state = LicenseState(
            status: .trial, record: nil,
            trial: TrialState(daysUsed: 29, lastUsedDate: "2026-07-10"), lastOnlineAt: now)
        #expect(LicensePresentation.statusText(for: state, isOnline: true, now: now) == "Trial — 1 day remaining")
    }

    @Test func validShowsLastVerifiedToday() {
        let state = LicenseState(
            status: .valid, record: record(lastValidated: now), trial: .initial, lastOnlineAt: now)
        #expect(
            LicensePresentation.statusText(for: state, isOnline: true, now: now)
                == "License active — last verified today")
    }

    @Test func validShowsLastVerifiedDaysAgo() {
        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let state = LicenseState(
            status: .valid, record: record(lastValidated: threeDaysAgo), trial: .initial, lastOnlineAt: now)
        #expect(
            LicensePresentation.statusText(for: state, isOnline: true, now: now)
                == "License active — last verified 3 days ago")
    }

    @Test func validShowsSingularDayAgo() {
        let oneDayAgo = now.addingTimeInterval(-1 * 24 * 60 * 60)
        let state = LicenseState(
            status: .valid, record: record(lastValidated: oneDayAgo), trial: .initial, lastOnlineAt: now)
        #expect(
            LicensePresentation.statusText(for: state, isOnline: true, now: now)
                == "License active — last verified 1 day ago")
    }

    @Test func validWithoutRecordReadsPlainly() {
        let state = LicenseState(status: .valid, record: nil, trial: .initial, lastOnlineAt: now)
        #expect(LicensePresentation.statusText(for: state, isOnline: true, now: now) == "License active")
    }

    @Test func expiredTrialAndExpiredLicenseReadDifferently() {
        let expiredTrial = LicenseState(
            status: .trialExpired, record: nil,
            trial: TrialState(daysUsed: 30, lastUsedDate: "2026-07-10"), lastOnlineAt: now)
        #expect(
            LicensePresentation.statusText(for: expiredTrial, isOnline: true, now: now)
                == "Trial expired — activate a license to keep using Sutto")

        let expiredLicense = LicenseState(
            status: .expired, record: record(lastValidated: now), trial: .initial, lastOnlineAt: now)
        #expect(
            LicensePresentation.statusText(for: expiredLicense, isOnline: true, now: now)
                == "License expired — renew or activate a new license")

        // `expired` always means the backend refused a license, so even an
        // unusual shape with no record keeps the license wording.
        let expiredWithoutRecord = LicenseState(
            status: .expired, record: nil, trial: .initial, lastOnlineAt: now)
        #expect(
            LicensePresentation.statusText(for: expiredWithoutRecord, isOnline: true, now: now)
                == "License expired — renew or activate a new license")
    }

    @Test func invalidReadsAsInvalid() {
        let state = LicenseState(
            status: .invalid, record: record(lastValidated: now), trial: .initial, lastOnlineAt: now)
        #expect(
            LicensePresentation.statusText(for: state, isOnline: true, now: now)
                == "License invalid — check your key and activate again")
    }

    // MARK: - Activation feedback

    @Test func activatedFeedbackIsSuccess() {
        let outcome = ActivationOutcome.activated(record: record(lastValidated: now))
        let feedback = LicensePresentation.activationFeedback(for: outcome)
        #expect(feedback.isSuccess)
        #expect(feedback.message == "License activated.")
    }

    @Test func noResponseFeedbackIsRetryable() {
        let feedback = LicensePresentation.activationFeedback(for: .noResponse)
        #expect(!feedback.isSuccess)
        #expect(feedback.message == "License server unavailable — try again")
    }

    @Test(arguments: [
        (AuthoritativeRejection.invalidKey, "License key not found"),
        (.invalidActivation, "This activation is not valid for this device"),
        (.expired, "Subscription has expired"),
        (.cancelled, "Subscription was cancelled"),
        (.deactivated, "This device's activation was revoked"),
    ])
    func rejectionFeedbackMapsEachReason(reason: AuthoritativeRejection, message: String) {
        let feedback = LicensePresentation.activationFeedback(for: .rejected(reason))
        #expect(!feedback.isSuccess)
        #expect(feedback.message == message)
    }

    // MARK: - Offline limit

    private static let offlineText =
        "Offline for too long — reconnect to the internet to keep using Sutto"

    private func valid(daysSinceLastOnline days: Double) -> LicenseState {
        LicenseState(
            status: .valid, record: record(lastValidated: now), trial: .initial,
            lastOnlineAt: now.addingTimeInterval(-days * 24 * 60 * 60))
    }

    @Test func validPastTheOfflineLimitShowsTheReconnectText() {
        #expect(
            LicensePresentation.statusText(
                for: valid(daysSinceLastOnline: 7), isOnline: false, now: now)
                == Self.offlineText)
    }

    @Test func validWithinTheOfflineLimitShowsTheUsualText() {
        #expect(
            LicensePresentation.statusText(
                for: valid(daysSinceLastOnline: 6), isOnline: false, now: now)
                == "License active — last verified today")
    }

    /// Online, a long-ago last-online time does not matter: it is about to be
    /// recorded again.
    @Test func validOnlineShowsTheUsualTextHoweverLongAgoLastOnlineWas() {
        #expect(
            LicensePresentation.statusText(
                for: valid(daysSinceLastOnline: 30), isOnline: true, now: now)
                == "License active — last verified today")
    }

    @Test func trialOfflineLongShowsTheTrialText() {
        let state = LicenseState(
            status: .trial, record: nil, trial: TrialState(daysUsed: 5, lastUsedDate: "2026-07-10"),
            lastOnlineAt: now.addingTimeInterval(-30 * 24 * 60 * 60))
        #expect(
            LicensePresentation.statusText(for: state, isOnline: false, now: now)
                == "Trial — 25 days remaining")
    }

    // MARK: - Spent trial and the license-server probe

    private static let reopenedTrialText =
        "Trial ended — Sutto stays available; a license supports its development"
    private static let lockedTrialText = "Trial expired — activate a license to keep using Sutto"

    private func spentTrial(
        trialProbe: TrialProbeResult, daysSinceLastOnline days: Double = 0
    ) -> LicenseState {
        LicenseState(
            status: .trialExpired, record: nil,
            trial: TrialState(daysUsed: 30, lastUsedDate: "2026-07-10"),
            lastOnlineAt: now.addingTimeInterval(-days * 24 * 60 * 60),
            trialProbeResult: trialProbe)
    }

    /// A spent trial opened because the license server no longer answers is
    /// not described as locked; it still mentions a license.
    @Test func trialProbeNoResponseShowsTheNonLockedText() {
        let state = spentTrial(trialProbe: .noResponse)
        #expect(state.isGateOpen(isOnline: true, now: now))
        #expect(
            LicensePresentation.statusText(for: state, isOnline: true, now: now)
                == Self.reopenedTrialText)
        #expect(
            LicensePresentation.statusText(
                for: spentTrial(trialProbe: .noResponse, daysSinceLastOnline: 3),
                isOnline: false, now: now) == Self.reopenedTrialText)
    }

    /// A spent trial that is closed — the server answered, or has not been
    /// asked yet — keeps the "Trial expired" wording.
    @Test(arguments: [TrialProbeResult.none, .answered])
    func trialProbeClosedShowsTheTrialExpiredText(trialProbe: TrialProbeResult) {
        let state = spentTrial(trialProbe: trialProbe)
        #expect(!state.isGateOpen(isOnline: true, now: now))
        #expect(
            LicensePresentation.statusText(for: state, isOnline: true, now: now)
                == Self.lockedTrialText)
    }

    /// A reopened spent trial offline for 7 days or more is closed by the
    /// offline limit and says so, like a `valid` device.
    @Test func trialProbeNoResponsePastTheOfflineLimitShowsTheReconnectText() {
        let state = spentTrial(trialProbe: .noResponse, daysSinceLastOnline: 7)
        #expect(!state.isGateOpen(isOnline: false, now: now))
        #expect(
            LicensePresentation.statusText(for: state, isOnline: false, now: now)
                == Self.offlineText)
    }

    /// A closed spent trial is closed by the server, not by the offline limit,
    /// so a long time offline keeps the "Trial expired" wording.
    @Test func trialProbeAnsweredOfflineLongKeepsTheTrialExpiredText() {
        let state = spentTrial(trialProbe: .answered, daysSinceLastOnline: 30)
        #expect(
            LicensePresentation.statusText(for: state, isOnline: false, now: now)
                == Self.lockedTrialText)
    }
}
