import Foundation

/// The last authoritative verdict about this device's license, and the sole
/// status axis the gate decision reads.
///
/// The macOS port of the GNOME `LicenseStatus` (`domain/licensing/license-status.ts`),
/// with the same four values. The raw strings match the GNOME statuses so the
/// persistence layer (a later sub-PR) can map them one-for-one; the domain
/// itself never inspects the raw value.
public enum LicenseStatus: String, Equatable, Sendable {
    /// No license activated yet — the local trial governs the gate.
    case trial
    /// A license was activated and last heard from the backend as good.
    /// Under the unlimited fail-open policy this stays enabled until the
    /// backend gives an authoritative NO (see ``LicenseGatePolicy``).
    case valid
    /// The backend authoritatively refused the license (expired / cancelled /
    /// deactivated device) — the gate closes.
    case expired
    /// The key or activation was authoritatively rejected as unusable — the
    /// gate closes.
    case invalid
}
