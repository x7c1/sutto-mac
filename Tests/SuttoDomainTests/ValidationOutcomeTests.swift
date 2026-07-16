import Foundation
import Testing

@testable import SuttoDomain

/// The validate-outcome → next-status mapping, the heart of fail-open: only an
/// authoritative rejection downgrades; a non-answer (offline / timeout / 5xx /
/// retired-API 404 / 410, all classified into `.noResponse` by infra) leaves
/// the cached status untouched. Ports GNOME's `handleValidationError`.
@Suite struct ValidationOutcomeTests {
    /// The most important case: a valid device whose validate did not get an
    /// authoritative answer stays `valid`. This is what makes "the API can
    /// disappear and valid devices keep working" true.
    @Test func noResponseKeepsTheCachedStatus() {
        #expect(ValidationOutcome.noResponse.resolvedStatus(from: .valid) == .valid)
        #expect(ValidationOutcome.noResponse.resolvedStatus(from: .trial) == .trial)
        #expect(ValidationOutcome.noResponse.resolvedStatus(from: .expired) == .expired)
        #expect(ValidationOutcome.noResponse.resolvedStatus(from: .invalid) == .invalid)
    }

    @Test func confirmationBecomesValid() {
        let outcome = ValidationOutcome.valid(validUntil: Date(timeIntervalSince1970: 2_000_000_000))
        #expect(outcome.resolvedStatus(from: .trial) == .valid)
        #expect(outcome.resolvedStatus(from: .valid) == .valid)
    }

    @Test func expiredRejectionDowngradesToExpired() {
        #expect(ValidationOutcome.rejected(.expired).resolvedStatus(from: .valid) == .expired)
    }

    @Test func cancelledRejectionDowngradesToExpired() {
        #expect(ValidationOutcome.rejected(.cancelled).resolvedStatus(from: .valid) == .expired)
    }

    @Test func deactivatedRejectionDowngradesToExpired() {
        #expect(ValidationOutcome.rejected(.deactivated).resolvedStatus(from: .valid) == .expired)
    }

    @Test func invalidKeyRejectionDowngradesToInvalid() {
        #expect(ValidationOutcome.rejected(.invalidKey).resolvedStatus(from: .valid) == .invalid)
    }

    @Test func invalidActivationRejectionDowngradesToInvalid() {
        #expect(ValidationOutcome.rejected(.invalidActivation).resolvedStatus(from: .valid) == .invalid)
    }
}
