import Foundation

/// The local, backend-independent trial: how many distinct days the app has
/// been used, and the last day counted.
///
/// The macOS port of the GNOME `TrialDays` + `TrialPeriod`
/// (`domain/licensing/trial-days.ts`, `trial-period.ts`) folded into one value
/// type. The trial is a day-of-use counter capped at ``maxDays`` (30); the
/// "day" is supplied by the caller as an opaque date string (an ISO date, say)
/// so the domain needs no clock and no calendar.
///
/// The count is self-healing on load: a stored value outside `0...maxDays` is
/// clamped rather than rejected, mirroring ``LayoutHistory``'s compact-on-load
/// and the licensing principle that corrupt storage must never fabricate a
/// worse verdict than the truth (design decision #8).
public struct TrialState: Equatable, Sendable {
    /// The trial length in days. Mirrors the GNOME `MAX_DAYS = 30`
    /// (`trial-days.ts`).
    public static let maxDays = 30

    /// Distinct days of use counted so far, always in `0...maxDays`.
    public let daysUsed: Int

    /// The last day counted, as the caller's date string; empty before the
    /// first day is recorded (GNOME's `TrialPeriod.initial` uses `''`).
    public let lastUsedDate: String

    /// Creates a trial state, clamping `daysUsed` into `0...maxDays`.
    public init(daysUsed: Int, lastUsedDate: String) {
        self.daysUsed = min(max(daysUsed, 0), Self.maxDays)
        self.lastUsedDate = lastUsedDate
    }

    /// A fresh trial: zero days used, no day recorded yet — the port of the
    /// GNOME `TrialPeriod.initial`. Also the degrade target when license
    /// storage is missing or corrupt (design decision #8).
    public static let initial = TrialState(daysUsed: 0, lastUsedDate: "")

    /// Days left before the trial expires; never negative.
    public var remainingDays: Int {
        Self.maxDays - daysUsed
    }

    /// Whether the trial has run its full length (GNOME's `isExpired`,
    /// `value >= MAX_DAYS`).
    public var isExpired: Bool {
        daysUsed >= Self.maxDays
    }

    /// Whether a usage day should be counted for `today`: only when today has
    /// not already been counted and the trial has not expired. The port of the
    /// GNOME `TrialPeriod.canRecordUsage` (`trial-period.ts:32-34`).
    public func canRecordUsage(today: String) -> Bool {
        lastUsedDate != today && !isExpired
    }

    /// The trial after counting a usage day for `today`, or `self` when today
    /// is not countable. Increments ``daysUsed`` (capped at ``maxDays``) and
    /// records `today`. The port of the GNOME `TrialPeriod.recordUsage`
    /// (`trial-period.ts:36-44`), with the cap from `TrialDays.increment`.
    public func recordUsage(today: String) -> TrialState {
        guard canRecordUsage(today: today) else { return self }
        return TrialState(daysUsed: daysUsed + 1, lastUsedDate: today)
    }
}
