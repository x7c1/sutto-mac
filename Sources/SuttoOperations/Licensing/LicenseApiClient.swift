import SuttoDomain

/// The backend for license activation and validation, implemented by the infra
/// layer.
///
/// The port of the GNOME `LicenseApiClient`
/// (`operations/licensing/license-api-client.ts`). Both calls return a
/// *classified* result — the HTTP details (status codes, timeouts, the
/// 404 / 410 that mean "API retired") are turned into these cases by the infra
/// client and never reach here, so the gate reasons only about "authoritative
/// yes / authoritative no / no answer" (design decision #2). This keeps the
/// fail-open rule provable without a network.
///
/// Marked `@MainActor` to match ``LicenseRepository`` and ``LicenseGate``: the
/// method bodies await the actual network off the main actor, so the isolation
/// costs nothing while letting the composition root and the tests share the
/// same simple, mutable stubs.
@MainActor
public protocol LicenseApiClient {
    /// Activates `key` for `device`. On success the returned
    /// ``LicenseRecord`` is ready to persist (its `status` is `.valid`).
    func activate(key: String, device: DeviceIdentity) async -> ActivationOutcome

    /// Validates the license identified by `key` / `activationId`. Reuses the
    /// domain ``SuttoDomain/ValidationOutcome`` so the status transition stays
    /// a pure mapping.
    func validate(key: String, activationId: String) async -> ValidationOutcome
}

/// An activation attempt reduced to the only distinctions the gate cares
/// about, mirroring ``SuttoDomain/ValidationOutcome`` for the activate path.
///
/// ``SuttoDomain/AuthoritativeRejection`` is reused rather than introducing a
/// second reason enum: activation rejections are the same authoritative NOs a
/// validate can carry. ``ActivationOutcome/activated(record:)`` carries a
/// fully built record (unlike validate, which only refreshes an existing one)
/// because activation is where a device first learns its `activationId`.
public enum ActivationOutcome: Equatable, Sendable {
    /// The backend activated the device; the record is ready to persist.
    case activated(record: LicenseRecord)

    /// The backend authoritatively refused the key or activation (an HTTP 4xx
    /// carrying a reason code) — the only signal that downgrades the status.
    case rejected(AuthoritativeRejection)

    /// The backend did not authoritatively answer: offline, timeout, 5xx, DNS
    /// failure, or a retired-API 404 / 410. The activation simply did not
    /// happen and can be retried; the cached status is left untouched.
    case noResponse
}
