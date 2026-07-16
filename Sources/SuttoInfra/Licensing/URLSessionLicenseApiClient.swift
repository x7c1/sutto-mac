import Foundation
import SuttoDomain
import SuttoOperations
import os

/// URLSession-backed ``SuttoOperations/LicenseApiClient``: the one place that
/// knows HTTP.
///
/// The port of the GNOME `HttpLicenseApiClient`
/// (`infra/api/http-license-api-client.ts`), with its 4xx handling corrected.
/// Its whole job is to turn a transport-level result (status code, body, or
/// thrown error) into the classified ``SuttoOperations/ActivationOutcome`` /
/// ``SuttoDomain/ValidationOutcome`` the rest of the app reasons about — so
/// the "authoritative NO vs. no answer" boundary (design decisions #2 and #3)
/// lives here and nowhere else.
///
/// The classification is a pair of **pure, `nonisolated static`** functions
/// (``classifyValidation(statusCode:data:error:)`` /
/// ``classifyActivation(statusCode:data:error:licenseKey:now:)``) kept apart
/// from the URLSession call, so the boundary is unit-tested directly without a
/// network or a stubbed session.
///
/// The base URL is injected: the backend is a later slice, so the composition
/// root supplies a placeholder for now and a real URL once it exists (design
/// "先行スライス" note).
public final class URLSessionLicenseApiClient: LicenseApiClient {
    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "licensing")

    /// - Parameters:
    ///   - baseURL: the backend root; requests are posted to
    ///     `/v1/license/activate` and `/v1/license/validate` under it.
    ///   - session: injectable for tests that drive a `URLProtocol` stub;
    ///     defaults to `.shared`.
    ///   - timeout: per-request timeout in seconds. Centralized here, matching
    ///     the GNOME client's 30 s (`http-license-api-client.ts`).
    public init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    public func activate(key: String, device: DeviceIdentity) async -> ActivationOutcome {
        let now = Date()
        let body = ActivationRequestBody(
            license_key: key, device_id: device.id, device_label: device.label)
        guard let request = makeRequest(path: "/v1/license/activate", body: body) else {
            return .noResponse
        }
        do {
            let (data, response) = try await session.data(for: request)
            return Self.classifyActivation(
                statusCode: Self.statusCode(of: response), data: data, error: nil,
                licenseKey: key, now: now)
        } catch {
            return Self.classifyActivation(
                statusCode: 0, data: nil, error: error, licenseKey: key, now: now)
        }
    }

    public func validate(key: String, activationId: String) async -> ValidationOutcome {
        let body = ValidationRequestBody(license_key: key, activation_id: activationId)
        guard let request = makeRequest(path: "/v1/license/validate", body: body) else {
            return .noResponse
        }
        do {
            let (data, response) = try await session.data(for: request)
            return Self.classifyValidation(
                statusCode: Self.statusCode(of: response), data: data, error: nil)
        } catch {
            return Self.classifyValidation(statusCode: 0, data: nil, error: error)
        }
    }

    // MARK: - Request building

    private func makeRequest(path: String, body: some Encodable) -> URLRequest? {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            logger.error("could not build license API URL for path \(path, privacy: .public)")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            logger.error(
                "could not encode license API request: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
        return request
    }

    private static func statusCode(of response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    // MARK: - Classification (pure)

    /// Classifies a validate response into a ``SuttoDomain/ValidationOutcome``.
    ///
    /// The boundary that makes fail-open true (design decisions #2 / #3):
    /// - a thrown transport `error` (offline, timeout, DNS) → `.noResponse`;
    /// - `2xx` with a parseable body → `.valid(validUntil:)` (an unparseable
    ///   `2xx` is treated as no answer, never a downgrade);
    /// - `404` / `410` → `.noResponse` — a retired API must not close the gate,
    ///   the specific fix over GNOME's blanket 4xx handling;
    /// - other `4xx` with a recognized reason code → `.rejected(...)`; an
    ///   unrecognized reason → `.noResponse`;
    /// - `5xx` and anything else → `.noResponse`.
    public nonisolated static func classifyValidation(
        statusCode: Int, data: Data?, error: Error?
    ) -> ValidationOutcome {
        if error != nil { return .noResponse }

        switch statusCode {
        case 200..<300:
            guard let data,
                let body = try? jsonDecoder.decode(ValidationResponseBody.self, from: data)
            else {
                return .noResponse
            }
            return .valid(validUntil: body.valid_until)
        case 404, 410:
            return .noResponse
        case 400..<500:
            guard let rejection = authoritativeRejection(from: data) else { return .noResponse }
            return .rejected(rejection)
        default:
            return .noResponse
        }
    }

    /// Classifies an activate response into an
    /// ``SuttoOperations/ActivationOutcome``. The status-code boundary matches
    /// ``classifyValidation(statusCode:data:error:)``; on success it builds the
    /// ``SuttoDomain/LicenseRecord`` from the response plus the caller's
    /// `licenseKey` and `now` (so the function stays pure and testable).
    public nonisolated static func classifyActivation(
        statusCode: Int, data: Data?, error: Error?, licenseKey: String, now: Date
    ) -> ActivationOutcome {
        if error != nil { return .noResponse }

        switch statusCode {
        case 200..<300:
            guard let data,
                let body = try? jsonDecoder.decode(ActivationResponseBody.self, from: data)
            else {
                return .noResponse
            }
            let record = LicenseRecord(
                licenseKey: licenseKey,
                activationId: body.activation_id,
                validUntil: body.valid_until,
                lastValidated: now,
                status: .valid
            )
            return .activated(record: record)
        case 404, 410:
            return .noResponse
        case 400..<500:
            guard let rejection = authoritativeRejection(from: data) else { return .noResponse }
            return .rejected(rejection)
        default:
            return .noResponse
        }
    }

    /// Maps a 4xx error body's `type` code to an
    /// ``SuttoDomain/AuthoritativeRejection``, or `nil` when the body is
    /// missing / unparseable or the code is unrecognized — in which case the
    /// caller degrades to `.noResponse` rather than inventing a downgrade
    /// (the GNOME fallback to `BACKEND_UNREACHABLE`).
    private nonisolated static func authoritativeRejection(
        from data: Data?
    ) -> AuthoritativeRejection? {
        guard let data,
            let body = try? jsonDecoder.decode(ErrorResponseBody.self, from: data)
        else {
            return nil
        }
        switch body.type {
        case "INVALID_LICENSE_KEY": return .invalidKey
        case "INVALID_ACTIVATION": return .invalidActivation
        case "LICENSE_EXPIRED": return .expired
        case "LICENSE_CANCELLED": return .cancelled
        case "DEVICE_DEACTIVATED": return .deactivated
        default: return nil
        }
    }

    private nonisolated static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Wire format

/// Request/response bodies mirroring the GNOME client's JSON contract
/// (snake_case keys). `valid_until` is an ISO-8601 timestamp, decoded with the
/// `.iso8601` strategy.
private struct ActivationRequestBody: Encodable {
    let license_key: String
    let device_id: String
    let device_label: String
}

private struct ValidationRequestBody: Encodable {
    let license_key: String
    let activation_id: String
}

private struct ActivationResponseBody: Decodable {
    let activation_id: String
    let valid_until: Date
}

private struct ValidationResponseBody: Decodable {
    let valid_until: Date
}

private struct ErrorResponseBody: Decodable {
    let type: String
}
