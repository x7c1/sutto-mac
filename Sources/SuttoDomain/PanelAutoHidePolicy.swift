import Foundation

/// Auto-hide decision logic for the layout panel: the panel hides after the
/// cursor has stayed outside it for a grace period. The macOS counterpart of
/// the GNOME version's `MainPanelAutoHide` (`ui/main-panel/auto-hide.ts`),
/// ported rule for rule:
///
/// - **The grace timer arms only on an exit transition.** GNOME starts the
///   timeout from the container's `leave-event`; a panel that opens with the
///   cursor already outside never receives one, so it stays up indefinitely
///   until the cursor visits and leaves — which is what makes opening the
///   panel by keyboard shortcut and navigating it by keyboard safe: no
///   enter/exit, no timer.
/// - **Re-entry cancels the pending hide** (`enter-event` clears the
///   timeout), and the next exit starts a fresh full grace period (GNOME's
///   `startAutoHideTimeout` clears any existing timeout before starting).
/// - **The fire is double-checked.** When the timeout fires, GNOME hides
///   only if the panel is still not hovered — mirrored by
///   ``shouldHideWhenHideTimerFires``, which guards against a stale timer
///   the shell failed to cancel.
/// - **Keyboard activity does not interact with auto-hide.** The GNOME
///   keyboard navigator never touches the hover state or the timeout: key
///   presses neither suspend nor reset a running grace period. The panel
///   survives keyboard navigation only through the exit-transition rule
///   above, not through any keyboard-driven reset.
/// - **Selecting a layout does not interact with auto-hide either.** The
///   GNOME selection handler applies the layout and leaves the panel (and
///   the timer) alone.
///
/// The policy is a pure state machine: transitions return an ``Effect``
/// telling the shell what to do with its one hide timer, so the domain
/// holds no real timer and the tests need no clock.
public struct PanelAutoHidePolicy: Equatable, Sendable {
    /// How long the cursor must stay outside the panel before it hides,
    /// in seconds. Mirrors the GNOME version's `AUTO_HIDE_DELAY_MS = 500`
    /// (`ui/constants.ts`) — a plain constant there (not a gschema
    /// setting), so it is a plain constant here.
    public static let autoHideDelay: TimeInterval = 0.5

    /// What the shell must do with its hide timer after a transition.
    public enum Effect: Equatable, Sendable {
        /// Cancel the pending hide, if any.
        case cancelScheduledHide
        /// Schedule a hide after `after` seconds, replacing any pending
        /// schedule (a fresh exit restarts the full grace period).
        case scheduleHide(after: TimeInterval)
    }

    /// Whether the cursor is currently over the panel, as reported by the
    /// shell's enter/exit events. GNOME's `isPanelHovered`.
    public private(set) var isPanelHovered = false

    public init() {}

    /// The panel was (re)shown: hover state resets and no hide is pending —
    /// GNOME's `show()` calls `resetHoverStates()`, and the preceding
    /// `hide()` already cleared the timeout (`cleanup()`); returning a
    /// cancel keeps that invariant even for a shell that reuses its panel
    /// without a hide in between.
    public mutating func panelShown() -> Effect {
        isPanelHovered = false
        return .cancelScheduledHide
    }

    /// The cursor entered the panel: any pending hide is cancelled
    /// (GNOME's `enter-event` handler).
    public mutating func cursorEntered() -> Effect {
        isPanelHovered = true
        return .cancelScheduledHide
    }

    /// The cursor left the panel: a hide is scheduled after the grace
    /// period (GNOME's `leave-event` handler).
    public mutating func cursorExited() -> Effect {
        isPanelHovered = false
        return .scheduleHide(after: Self.autoHideDelay)
    }

    /// The panel was hidden (for any reason): any pending hide is
    /// cancelled and hover state resets (GNOME's `cleanup()`).
    public mutating func panelHidden() -> Effect {
        isPanelHovered = false
        return .cancelScheduledHide
    }

    /// Whether an elapsed grace period should actually hide the panel —
    /// GNOME double-checks `isPanelHovered` when the timeout fires, so a
    /// stale timer that survived a re-entry cannot hide a hovered panel.
    public var shouldHideWhenHideTimerFires: Bool {
        !isPanelHovered
    }
}
