import Foundation
import SuttoDomain
import SuttoOperations

/// Reads the macOS built-in edge-tiling setting straight from the
/// `com.apple.WindowManager` preference domain
/// (`EnableTilingByEdgeDrag`), the toggle behind System Settings ›
/// Desktop & Dock › "Drag windows to screen edges to tile".
///
/// Uses only the public `CFPreferences` API (no private frameworks — the Mac
/// App Store is a future target). The value is read FRESH on every call: the
/// user can flip the toggle while Sutto is running, so a cached read would go
/// stale. `CFPreferencesAppSynchronize` drops any per-process cfprefs cache
/// before the copy so the read reflects the current on-disk value.
///
/// The "absent → enabled" interpretation lives in the pure
/// ``SuttoDomain/SystemEdgeTilingPolicy`` (unit-tested there); this adapter
/// only performs the raw read and composes the two.
@MainActor
public struct WindowManagerEdgeTilingDetector: EdgeTilingDetecting {
    static let applicationID = "com.apple.WindowManager"
    static let key = "EnableTilingByEdgeDrag"

    public init() {}

    public func isSystemEdgeTilingEnabled() -> Bool {
        SystemEdgeTilingPolicy.isEnabled(from: rawValue())
    }

    /// The current stored value, or `nil` when the key has never been
    /// written (the default-ON case on Sequoia).
    private func rawValue() -> Bool? {
        let applicationID = Self.applicationID as CFString
        // Drop any cached copy so a mid-session toggle is picked up.
        CFPreferencesAppSynchronize(applicationID)
        guard
            let value = CFPreferencesCopyAppValue(Self.key as CFString, applicationID)
        else {
            return nil
        }
        // The toggle stores a CFBoolean; NSNumber bridges both CFBoolean and
        // any CFNumber a hand-edit might leave, so read through it.
        return (value as? NSNumber)?.boolValue
    }
}
