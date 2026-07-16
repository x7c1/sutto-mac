import Foundation

/// The single gate decision: whether the app's gated features (panel display)
/// are unlocked, given the last authoritative status and the local trial.
///
/// The macOS port of the GNOME `shouldExtensionBeEnabled`
/// (`operations/licensing/license-operations.ts:124-140`), simplified to the
/// unlimited fail-open policy this product adopts from the start
/// (design decisions #1 and #6; the canonical policy lives in the
/// `0222-license-api` graceful-degradation spec):
///
/// - `valid` → **open, unconditionally.** GNOME gated a valid-but-offline
///   device on `daysSinceLastValidation < OFFLINE_GRACE_PERIOD_DAYS (7)`;
///   both the offline branch and the 7-day grace are dropped. A valid device
///   stays open until the backend gives an authoritative NO (which turns
///   `status` into `.expired` / `.invalid` elsewhere), so a backend that is
///   merely unreachable — or has vanished entirely (404 / 410 / DNS) — never
///   closes the gate.
/// - `trial` → open while the local trial has days left.
/// - `expired` / `invalid` → closed.
///
/// The decision reads **only** `status` and `trial`. No staleness, no live
/// network state, no clock — those never reach this policy, which is what
/// keeps ``SuttoDomain`` Foundation-only and makes "the API can disappear and
/// valid devices keep working" a property provable by a pure unit test.
public enum LicenseGatePolicy {
    /// Whether the gate is open for the given status and trial.
    public static func isGateOpen(status: LicenseStatus, trial: TrialState) -> Bool {
        switch status {
        case .valid:
            return true
        case .trial:
            return !trial.isExpired
        case .expired, .invalid:
            return false
        }
    }
}
