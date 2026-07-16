import Foundation
import SuttoDomain
import SuttoOperations
import Testing

@testable import SuttoInfra

/// Tests for the HTTP → outcome classification boundary of
/// ``URLSessionLicenseApiClient`` — the pure, `nonisolated static` functions
/// that decide "authoritative yes / authoritative no / no answer".
///
/// These are the operations-independent half of the "the API can disappear and
/// a valid device keeps working" fixture: 5xx / timeout / 404 / 410 must all
/// classify to `.noResponse` so the gate never downgrades, and only a 4xx with
/// a recognized reason code becomes an authoritative rejection.
@Suite struct URLSessionLicenseApiClientTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func errorBody(_ type: String) -> Data {
        Data(#"{"type":"\#(type)"}"#.utf8)
    }

    private func validationBody(validUntil: String) -> Data {
        Data(#"{"valid_until":"\#(validUntil)","subscription_status":"active"}"#.utf8)
    }

    private func activationBody(activationId: String, validUntil: String) -> Data {
        Data(
            #"{"activation_id":"\#(activationId)","valid_until":"\#(validUntil)","devices_used":1,"devices_limit":3,"deactivated_device":null}"#
                .utf8)
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso)!
    }

    // MARK: - Validation

    @Test func validationSuccessParsesValidUntil() {
        let outcome = URLSessionLicenseApiClient.classifyValidation(
            statusCode: 200,
            data: validationBody(validUntil: "2027-01-01T00:00:00Z"),
            error: nil)

        #expect(outcome == .valid(validUntil: date("2027-01-01T00:00:00Z")))
    }

    @Test func validationExpiredReasonRejects() {
        let outcome = URLSessionLicenseApiClient.classifyValidation(
            statusCode: 403, data: errorBody("LICENSE_EXPIRED"), error: nil)

        #expect(outcome == .rejected(.expired))
    }

    @Test func validationDeactivatedReasonRejects() {
        let outcome = URLSessionLicenseApiClient.classifyValidation(
            statusCode: 403, data: errorBody("DEVICE_DEACTIVATED"), error: nil)

        #expect(outcome == .rejected(.deactivated))
    }

    @Test func validationInvalidKeyReasonRejects() {
        let outcome = URLSessionLicenseApiClient.classifyValidation(
            statusCode: 400, data: errorBody("INVALID_LICENSE_KEY"), error: nil)

        #expect(outcome == .rejected(.invalidKey))
    }

    /// The heart of the fix over GNOME: a retired API (404 / 410) is a
    /// non-answer, not an authoritative NO.
    @Test func validationTreats404And410AsNoResponse() {
        #expect(
            URLSessionLicenseApiClient.classifyValidation(
                statusCode: 404, data: errorBody("LICENSE_EXPIRED"), error: nil) == .noResponse)
        #expect(
            URLSessionLicenseApiClient.classifyValidation(
                statusCode: 410, data: nil, error: nil) == .noResponse)
    }

    @Test func validationTreats5xxAsNoResponse() {
        #expect(
            URLSessionLicenseApiClient.classifyValidation(
                statusCode: 500, data: nil, error: nil) == .noResponse)
        #expect(
            URLSessionLicenseApiClient.classifyValidation(
                statusCode: 503, data: nil, error: nil) == .noResponse)
    }

    @Test func validationTreatsTransportErrorAsNoResponse() {
        let outcome = URLSessionLicenseApiClient.classifyValidation(
            statusCode: 0, data: nil, error: URLError(.timedOut))

        #expect(outcome == .noResponse)
    }

    @Test func validationTreatsConnectionFailureAsNoResponse() {
        let outcome = URLSessionLicenseApiClient.classifyValidation(
            statusCode: 0, data: nil, error: URLError(.cannotConnectToHost))

        #expect(outcome == .noResponse)
    }

    /// An unrecognized 4xx reason code degrades to a non-answer rather than
    /// inventing a downgrade.
    @Test func validationTreatsUnknownReasonAsNoResponse() {
        let outcome = URLSessionLicenseApiClient.classifyValidation(
            statusCode: 400, data: errorBody("SOMETHING_NEW"), error: nil)

        #expect(outcome == .noResponse)
    }

    /// An unparseable 2xx body is a non-answer, never a downgrade.
    @Test func validationTreatsUnparseableSuccessAsNoResponse() {
        let outcome = URLSessionLicenseApiClient.classifyValidation(
            statusCode: 200, data: Data("not json".utf8), error: nil)

        #expect(outcome == .noResponse)
    }

    // MARK: - Activation

    @Test func activationSuccessBuildsAValidRecord() {
        let outcome = URLSessionLicenseApiClient.classifyActivation(
            statusCode: 200,
            data: activationBody(activationId: "ACT-789", validUntil: "2027-06-01T00:00:00Z"),
            error: nil,
            licenseKey: "KEY-123",
            now: now)

        #expect(
            outcome
                == .activated(
                    record: LicenseRecord(
                        licenseKey: "KEY-123",
                        activationId: "ACT-789",
                        validUntil: date("2027-06-01T00:00:00Z"),
                        lastValidated: now,
                        status: .valid)))
    }

    @Test func activationInvalidKeyReasonRejects() {
        let outcome = URLSessionLicenseApiClient.classifyActivation(
            statusCode: 400, data: errorBody("INVALID_LICENSE_KEY"), error: nil,
            licenseKey: "KEY", now: now)

        #expect(outcome == .rejected(.invalidKey))
    }

    @Test func activationExpiredReasonRejects() {
        let outcome = URLSessionLicenseApiClient.classifyActivation(
            statusCode: 403, data: errorBody("LICENSE_EXPIRED"), error: nil,
            licenseKey: "KEY", now: now)

        #expect(outcome == .rejected(.expired))
    }

    @Test func activationTreats404And410AsNoResponse() {
        #expect(
            URLSessionLicenseApiClient.classifyActivation(
                statusCode: 404, data: nil, error: nil, licenseKey: "KEY", now: now) == .noResponse)
        #expect(
            URLSessionLicenseApiClient.classifyActivation(
                statusCode: 410, data: nil, error: nil, licenseKey: "KEY", now: now) == .noResponse)
    }

    @Test func activationTreats5xxAsNoResponse() {
        let outcome = URLSessionLicenseApiClient.classifyActivation(
            statusCode: 500, data: nil, error: nil, licenseKey: "KEY", now: now)

        #expect(outcome == .noResponse)
    }

    @Test func activationTreatsTransportErrorAsNoResponse() {
        let outcome = URLSessionLicenseApiClient.classifyActivation(
            statusCode: 0, data: nil, error: URLError(.timedOut), licenseKey: "KEY", now: now)

        #expect(outcome == .noResponse)
    }
}
