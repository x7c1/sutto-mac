import Foundation
import Testing

@testable import SuttoDomain

/// ``LicenseRecord`` carries the activated-license fields. Its only derived
/// value, ``LicenseRecord/daysSinceLastValidation(now:)``, is UI-only text:
/// these tests pin the computation and pin that staleness plays no part in the
/// gate decision (design decisions #1 and #5).
@Suite struct LicenseRecordTests {
    private func record(
        lastValidated: Date,
        validUntil: Date = Date(timeIntervalSince1970: 2_000_000_000),
        status: LicenseStatus = .valid
    ) -> LicenseRecord {
        LicenseRecord(
            licenseKey: "KEY-123",
            activationId: "activation-abc",
            validUntil: validUntil,
            lastValidated: lastValidated,
            status: status
        )
    }

    @Test func daysSinceLastValidationCountsFractionalDays() {
        let lastValidated = Date(timeIntervalSince1970: 1_000_000_000)
        let now = lastValidated.addingTimeInterval(36 * 60 * 60)  // 1.5 days
        #expect(record(lastValidated: lastValidated).daysSinceLastValidation(now: now) == 1.5)
    }

    /// The gate reads only `status` and the trial, never the record's
    /// staleness: a valid device that has not validated in years is still
    /// open. This is the structural guarantee behind unlimited fail-open —
    /// ``LicenseGatePolicy/isGateOpen(status:trial:)`` cannot even see
    /// `lastValidated`.
    @Test func gateIgnoresHowStaleTheValidationIs() {
        let ancient = record(lastValidated: Date(timeIntervalSince1970: 0))
        #expect(ancient.daysSinceLastValidation(now: Date(timeIntervalSince1970: 2_000_000_000)) > 20_000)
        #expect(LicenseGatePolicy.isGateOpen(status: ancient.status, trial: .initial))
    }
}
