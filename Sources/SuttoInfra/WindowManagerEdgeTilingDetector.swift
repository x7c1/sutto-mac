import Foundation
import SuttoDomain
import SuttoOperations

/// Reads the macOS built-in window-tiling settings straight from the
/// `com.apple.WindowManager` preference domain — the toggles in System
/// Settings › Desktop & Dock:
///
/// - `EnableTilingByEdgeDrag` — "Drag windows to screen edges to tile".
/// - `EnableTopTilingByEdgeDrag` — "Drag windows to menu bar to fill screen".
///
/// Uses only the public `CFPreferences` API (no private frameworks — the Mac
/// App Store is a future target). Values are read FRESH on every call: the
/// user can flip a toggle while Sutto is running, so a cached read would go
/// stale. `CFPreferencesAppSynchronize` drops any per-process cfprefs cache
/// before the copies so the reads reflect the current on-disk values.
///
/// The "absent → enabled" interpretation lives in the pure
/// ``SuttoDomain/SystemEdgeTilingPolicy`` (unit-tested there); this adapter
/// only performs the raw reads and composes them into an
/// ``SuttoDomain/EdgeTilingConflicts``.
@MainActor
public struct WindowManagerEdgeTilingDetector: EdgeTilingDetecting {
    static let applicationID = "com.apple.WindowManager"
    static let edgeTilingKey = "EnableTilingByEdgeDrag"
    static let menuBarFillKey = "EnableTopTilingByEdgeDrag"

    public init() {}

    public func detectConflicts() -> EdgeTilingConflicts {
        // Drop any cached copy once so both reads below reflect a mid-session
        // toggle of either setting.
        CFPreferencesAppSynchronize(Self.applicationID as CFString)
        return SystemEdgeTilingPolicy.conflicts(
            edgeTilingRawValue: rawValue(forKey: Self.edgeTilingKey),
            menuBarFillRawValue: rawValue(forKey: Self.menuBarFillKey)
        )
    }

    /// The current stored value for `key`, or `nil` when it has never been
    /// written (the default-ON case on Sequoia).
    private func rawValue(forKey key: String) -> Bool? {
        let applicationID = Self.applicationID as CFString
        guard
            let value = CFPreferencesCopyAppValue(key as CFString, applicationID)
        else {
            return nil
        }
        // The toggle stores a CFBoolean; NSNumber bridges both CFBoolean and
        // any CFNumber a hand-edit might leave, so read through it.
        return (value as? NSNumber)?.boolValue
    }
}
