import Foundation

/// A validate attempt reduced to the only distinction the gate cares about:
/// did the backend authoritatively answer, and if so what.
///
/// This is the Domain-facing result of a validate — the HTTP details
/// (status codes, timeouts, the 404 / 410 that mean "API retired") are
/// classified into these cases by the infra client (a later sub-PR) and never
/// reach the domain. Keeping the boundary here lets the status transition be a
/// pure mapping, testable with no network.
public enum ValidationOutcome: Equatable, Sendable {
    /// The backend confirmed the license, with a refreshed expiry.
    case valid(validUntil: Date)

    /// The backend authoritatively refused the license (an HTTP 4xx carrying
    /// a reason code). This is the *only* signal that downgrades a device.
    case rejected(AuthoritativeRejection)

    /// The backend did not authoritatively answer: offline, timeout, 5xx, DNS
    /// failure, or a retired-API 404 / 410. Under unlimited fail-open this is
    /// **never** a downgrade — the cached status is kept as-is.
    case noResponse

    /// The license status after applying this outcome to `current`.
    ///
    /// The port of the GNOME `handleValidationError`
    /// (`operations/licensing/license-operations.ts:284-302`) as a pure
    /// mapping: an authoritative rejection downgrades, a confirmation becomes
    /// `valid`, and — the heart of fail-open — a non-answer leaves `current`
    /// untouched. Deliberately independent of ``LicenseRecord/lastValidated``:
    /// staleness plays no part in the transition.
    public func resolvedStatus(from current: LicenseStatus) -> LicenseStatus {
        switch self {
        case .valid:
            return .valid
        case .rejected(let rejection):
            return rejection.resultingStatus
        case .noResponse:
            return current
        }
    }
}

/// The authoritative reasons a backend can refuse a license, and the status
/// each maps to.
///
/// These are the reason codes GNOME's `handleValidationError` branches on;
/// classifying the HTTP response into one of them is the infra client's job
/// (a later sub-PR), so the domain sees only the classified reason.
public enum AuthoritativeRejection: Equatable, Sendable {
    /// The subscription period ended (`LICENSE_EXPIRED`).
    case expired
    /// The subscription was cancelled (`LICENSE_CANCELLED`).
    case cancelled
    /// This device's activation was revoked (`DEVICE_DEACTIVATED`).
    case deactivated
    /// The license key was not recognized (`INVALID_LICENSE_KEY`).
    case invalidKey
    /// The activation is not usable for this key/device.
    case invalidActivation

    /// The ``LicenseStatus`` this rejection downgrades a device to: the
    /// subscription-lifecycle reasons close the gate as `expired`, the
    /// key/activation reasons as `invalid` — matching GNOME's split between
    /// `setStatus('expired')` and `setStatus('invalid')`.
    public var resultingStatus: LicenseStatus {
        switch self {
        case .expired, .cancelled, .deactivated:
            return .expired
        case .invalidKey, .invalidActivation:
            return .invalid
        }
    }
}
