import Foundation

/// The result of the last time the license server was asked, after the trial
/// was spent, whether it is still there.
///
/// The macOS port of the GNOME `TrialProbeResult`
/// (`domain/licensing/trial-probe-result.ts`), with the same raw values so the
/// persistence layer maps them one-for-one.
///
/// The license gate is a reminder, not enforcement: a spent trial stays closed
/// while the license server answers, and opens once it no longer does, so
/// retiring the server never strands anyone (see ``LicenseGatePolicy``).
public enum TrialProbeResult: String, Equatable, Sendable {
    /// The license server has not been asked yet.
    case none
    /// The license server answered — it accepted or refused the request.
    case answered
    /// The license server did not answer.
    case noResponse = "no-response"

    /// The result a probe produced, classified like any validate: an
    /// acceptance and an authoritative refusal both mean the server answered;
    /// only ``ValidationOutcome/noResponse`` means it did not. The port of the
    /// GNOME `trialProbeResultOf`.
    public init(outcome: ValidationOutcome) {
        switch outcome {
        case .valid, .rejected:
            self = .answered
        case .noResponse:
            self = .noResponse
        }
    }
}
