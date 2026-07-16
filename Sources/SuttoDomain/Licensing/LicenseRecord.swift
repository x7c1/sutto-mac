import Foundation

/// The activated-license aggregate: the key and activation this device holds,
/// the backend's last verdict, and the timestamps around it.
///
/// The macOS port of the GNOME `License` (`domain/licensing/license.ts`),
/// reduced to a pure value type with no clock — any "how long ago" question
/// takes `now` as an argument, keeping ``SuttoDomain`` Foundation-only and the
/// type testable without a real clock (the same convention as
/// ``MonitorEnvironmentStorage`` and ``LayoutHistory``).
///
/// This record exists only while a license has been activated; a device that
/// has never activated is represented by ``TrialState`` alone.
public struct LicenseRecord: Equatable, Sendable {
    /// The license key entered at activation. Kept opaque here — the domain
    /// never parses or validates its shape.
    public let licenseKey: String

    /// The per-device activation identifier the backend returned.
    public let activationId: String

    /// When the current subscription period runs out, per the last validate.
    /// Informational for the UI; the gate decision does **not** read it (the
    /// authoritative expiry signal is `status == .expired`, set only by an
    /// authoritative NO — see ``ValidationOutcome``).
    public var validUntil: Date

    /// When the backend last answered a validate for this device. Used only
    /// to render "last checked N days ago" in the UI via
    /// ``daysSinceLastValidation(now:)``; deliberately **not** an input to the
    /// gate, so an unreachable backend can never age a valid device out
    /// (unlimited fail-open — see ``LicenseGatePolicy``).
    public var lastValidated: Date

    /// The last authoritative verdict for this device.
    public var status: LicenseStatus

    public init(
        licenseKey: String,
        activationId: String,
        validUntil: Date,
        lastValidated: Date,
        status: LicenseStatus
    ) {
        self.licenseKey = licenseKey
        self.activationId = activationId
        self.validUntil = validUntil
        self.lastValidated = lastValidated
        self.status = status
    }

    /// Fractional days since the last successful validate, as of `now`.
    ///
    /// The port of the GNOME `License.daysSinceLastValidation`
    /// (`license.ts:43-47`), but demoted to UI-only text: unlike GNOME, no
    /// gate path reads it. Injecting `now` keeps the computation pure.
    public func daysSinceLastValidation(now: Date) -> Double {
        now.timeIntervalSince(lastValidated) / (24 * 60 * 60)
    }
}
