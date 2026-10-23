import Foundation
import SuttoDomain
import Testing

@testable import SuttoInfra

/// Tests for the requests ``URLSessionLicenseApiClient`` puts on the wire,
/// driven through a `URLProtocol` stub so no network is touched.
///
/// The centrepiece is the trial probe: after the trial is spent, the launch
/// pass asks the license server whether it is still there with an ordinary
/// validate carrying an empty license key and an empty activation id. The
/// client must send those empty strings as-is rather than short-circuiting
/// them, or the probe would never reach the server and could never find it
/// answering.
@Suite(.serialized) @MainActor struct URLSessionLicenseApiClientRequestTests {
    private func makeClient() -> URLSessionLicenseApiClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        return URLSessionLicenseApiClient(
            baseURL: URL(string: "https://license.example.invalid")!,
            session: URLSession(configuration: configuration))
    }

    private func jsonBody(of request: URLRequest?) throws -> [String: Any] {
        let request = try #require(request)
        let data = try #require(RecordingURLProtocol.bodyData(of: request))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The trial probe: a validate with an empty key and activation id is
    /// posted to the validate endpoint with both empty strings in the body.
    @Test func trialProbeSendsTheEmptyKeyAndActivationIdAsIs() async throws {
        RecordingURLProtocol.reset(statusCode: 400, body: #"{"type":"INVALID_LICENSE_KEY"}"#)
        let client = makeClient()

        let outcome = await client.validate(key: "", activationId: "")

        let request = RecordingURLProtocol.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/v1/license/validate")
        let body = try jsonBody(of: request)
        #expect(body["license_key"] as? String == "")
        #expect(body["activation_id"] as? String == "")
        // The server answered (it refused the empty key), so the probe result
        // is `answered`.
        #expect(outcome == .rejected(.invalidKey))
        #expect(TrialProbeResult(outcome: outcome) == .answered)
    }

    /// A regular validate carries the stored key and activation id the same
    /// way, so the probe differs only in the values.
    @Test func validateSendsTheKeyAndActivationId() async throws {
        RecordingURLProtocol.reset(statusCode: 503, body: "")
        let client = makeClient()

        _ = await client.validate(key: "KEY-123", activationId: "ACT-456")

        let body = try jsonBody(of: RecordingURLProtocol.lastRequest)
        #expect(body["license_key"] as? String == "KEY-123")
        #expect(body["activation_id"] as? String == "ACT-456")
    }
}

/// A `URLProtocol` that records the last request and answers with a scripted
/// status code and body. Its state is static because `URLSession` instantiates
/// the protocol itself; the suite is serialized so tests never share it
/// concurrently.
private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recordedRequest: URLRequest?
    nonisolated(unsafe) private static var statusCode = 200
    nonisolated(unsafe) private static var responseBody = Data()

    static var lastRequest: URLRequest? {
        lock.withLock { recordedRequest }
    }

    static func reset(statusCode: Int, body: String) {
        lock.withLock {
            recordedRequest = nil
            self.statusCode = statusCode
            responseBody = Data(body.utf8)
        }
    }

    /// The request body: `URLSession` moves `httpBody` into
    /// `httpBodyStream` before a protocol sees the request, so read either.
    static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Capture the body now: the stream can be read only once.
        var captured = request
        captured.httpBody = Self.bodyData(of: request)
        let (statusCode, body) = Self.lock.withLock {
            Self.recordedRequest = captured
            return (Self.statusCode, Self.responseBody)
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
