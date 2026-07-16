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
            status: .trial, record: nil, trial: TrialState(daysUsed: 5, lastUsedDate: "2026-07-10"))
        #expect(
            LicensePresentation.statusText(for: state, now: now) == "Trial — 25 days remaining")
    }

    @Test func trialShowsSingularDayAtOneRemaining() {
        let state = LicenseState(
            status: .trial, record: nil,
            trial: TrialState(daysUsed: 29, lastUsedDate: "2026-07-10"))
        #expect(LicensePresentation.statusText(for: state, now: now) == "Trial — 1 day remaining")
    }

    @Test func validShowsLastVerifiedToday() {
        let state = LicenseState(
            status: .valid, record: record(lastValidated: now), trial: .initial)
        #expect(
            LicensePresentation.statusText(for: state, now: now)
                == "License active — last verified today")
    }

    @Test func validShowsLastVerifiedDaysAgo() {
        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let state = LicenseState(
            status: .valid, record: record(lastValidated: threeDaysAgo), trial: .initial)
        #expect(
            LicensePresentation.statusText(for: state, now: now)
                == "License active — last verified 3 days ago")
    }

    @Test func validShowsSingularDayAgo() {
        let oneDayAgo = now.addingTimeInterval(-1 * 24 * 60 * 60)
        let state = LicenseState(
            status: .valid, record: record(lastValidated: oneDayAgo), trial: .initial)
        #expect(
            LicensePresentation.statusText(for: state, now: now)
                == "License active — last verified 1 day ago")
    }

    @Test func validWithoutRecordReadsPlainly() {
        let state = LicenseState(status: .valid, record: nil, trial: .initial)
        #expect(LicensePresentation.statusText(for: state, now: now) == "License active")
    }

    @Test func expiredTrialAndExpiredLicenseReadDifferently() {
        let expiredTrial = LicenseState(
            status: .expired, record: nil,
            trial: TrialState(daysUsed: 30, lastUsedDate: "2026-07-10"))
        #expect(
            LicensePresentation.statusText(for: expiredTrial, now: now)
                == "Trial expired — activate a license to keep using Sutto")

        let expiredLicense = LicenseState(
            status: .expired, record: record(lastValidated: now), trial: .initial)
        #expect(
            LicensePresentation.statusText(for: expiredLicense, now: now)
                == "License expired — renew or activate a new license")
    }

    @Test func invalidReadsAsInvalid() {
        let state = LicenseState(
            status: .invalid, record: record(lastValidated: now), trial: .initial)
        #expect(
            LicensePresentation.statusText(for: state, now: now)
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
}
