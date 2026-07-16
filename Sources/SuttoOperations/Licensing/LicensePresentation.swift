import Foundation
import SuttoDomain

/// Pure mappings from the licensing aggregate to the human-readable strings the
/// UI shows — the current-status line and the feedback after an activation
/// attempt.
///
/// Kept out of the AppKit views (``SuttoUI``) so the wording is unit-testable
/// with no window: the License settings pane and the status-menu row both read
/// these, so the two surfaces can never describe the same state differently.
/// English-only for now, matching the rest of the app (no localization layer
/// exists yet); when one lands these become its lookup keys.
public enum LicensePresentation {
    /// A one-line description of the current gate state, for the settings pane's
    /// status label and the status-menu row.
    ///
    /// `now` is injected (rather than read here) so the "last verified N days
    /// ago" text is testable without a real clock, matching the rest of the
    /// licensing layer.
    public static func statusText(for state: LicenseState, now: Date) -> String {
        switch state.status {
        case .trial:
            let days = state.trial.remainingDays
            return "Trial — \(days) \(dayWord(days)) remaining"
        case .valid:
            guard let record = state.record else {
                // A valid status with no record is an unusual stored shape; the
                // gate is still open, so describe it plainly rather than as an
                // error.
                return "License active"
            }
            return "License active — \(lastVerifiedText(for: record, now: now))"
        case .expired:
            // The same status covers a spent trial and an authoritatively
            // expired license; the presence of a record tells them apart.
            return state.record == nil
                ? "Trial expired — activate a license to keep using Sutto"
                : "License expired — renew or activate a new license"
        case .invalid:
            return "License invalid — check your key and activate again"
        }
    }

    /// The feedback to show after an ``ActivationOutcome``: whether it succeeded
    /// and the message to display. The rejection wording follows the GNOME
    /// version's `errorMessages` (`license-operations.ts`), and a no-answer is
    /// reported as retryable — the state placed under the placeholder backend
    /// (design decision: real base URL is a later slice), so activation returns
    /// ``ActivationOutcome/noResponse`` until then.
    public static func activationFeedback(
        for outcome: ActivationOutcome
    ) -> LicenseActivationFeedback {
        switch outcome {
        case .activated:
            return LicenseActivationFeedback(isSuccess: true, message: "License activated.")
        case .rejected(let rejection):
            return LicenseActivationFeedback(
                isSuccess: false, message: rejectionMessage(for: rejection))
        case .noResponse:
            return LicenseActivationFeedback(
                isSuccess: false, message: "License server unavailable — try again")
        }
    }

    /// The message for an authoritative rejection, ported from the GNOME
    /// `errorMessages` map.
    private static func rejectionMessage(for rejection: AuthoritativeRejection) -> String {
        switch rejection {
        case .invalidKey:
            return "License key not found"
        case .invalidActivation:
            return "This activation is not valid for this device"
        case .expired:
            return "Subscription has expired"
        case .cancelled:
            return "Subscription was cancelled"
        case .deactivated:
            return "This device's activation was revoked"
        }
    }

    /// "last verified today" / "1 day ago" / "N days ago", flooring the
    /// fractional day count so "today" covers the first 24 hours.
    private static func lastVerifiedText(for record: LicenseRecord, now: Date) -> String {
        let days = Int(record.daysSinceLastValidation(now: now).rounded(.down))
        if days <= 0 {
            return "last verified today"
        }
        return "last verified \(days) \(dayWord(days)) ago"
    }

    private static func dayWord(_ count: Int) -> String {
        count == 1 ? "day" : "days"
    }
}

/// The result of mapping an ``ActivationOutcome`` to displayable feedback: a
/// message plus whether the activation succeeded, so the caller can style it
/// (success vs. error) without re-inspecting the outcome.
public struct LicenseActivationFeedback: Equatable, Sendable {
    public let isSuccess: Bool
    public let message: String

    public init(isSuccess: Bool, message: String) {
        self.isSuccess = isSuccess
        self.message = message
    }
}
