import Foundation

/// The last authoritative verdict about this device's license, and the
/// status axis the gate decision reads (alongside connectivity — see
/// ``LicenseGatePolicy``).
///
/// The macOS port of the GNOME `LicenseStatus` (`domain/licensing/license-status.ts`),
/// with the same five values. The raw strings match the GNOME statuses so the
/// persistence layer can map them one-for-one; the domain itself never
/// inspects the raw value.
///
/// Only an answer from the license server produces `expired` or `invalid`.
/// The two trial statuses are local: `trial` turns into `trialExpired` when
/// the day that spends the 30-day trial is recorded, so a spent trial and an
/// authoritatively expired license are told apart by the status alone.
public enum LicenseStatus: String, Equatable, Sendable {
    /// No license activated yet, and the local trial still has days left.
    case trial
    /// No license activated, and the local 30-day trial is spent — the gate
    /// closes. Unlike `expired`, no backend said so.
    case trialExpired = "trial-expired"
    /// A license was activated and last heard from the backend as good.
    /// Under the fail-open policy no backend silence ever downgrades it; it
    /// stays enabled until the backend gives an authoritative NO, unless the
    /// device has been offline for too long (see ``LicenseGatePolicy``).
    case valid
    /// The backend authoritatively refused the license (expired / cancelled /
    /// deactivated device) — the gate closes.
    case expired
    /// The key or activation was authoritatively rejected as unusable — the
    /// gate closes.
    case invalid
}
