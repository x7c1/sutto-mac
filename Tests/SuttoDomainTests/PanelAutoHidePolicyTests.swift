import Testing

@testable import SuttoDomain

/// State-transition coverage for the auto-hide policy, mirroring the GNOME
/// `MainPanelAutoHide` semantics it ports. The policy is a pure state
/// machine whose effects instruct the shell's timer, so no real timers (or
/// clocks) are involved — "the timer fired" is the shell asking
/// `shouldHideWhenHideTimerFires`.
@Suite struct PanelAutoHidePolicyTests {
    @Test func opensUnhovered() {
        let policy = PanelAutoHidePolicy()
        #expect(!policy.isPanelHovered)
    }

    @Test func graceDelayMirrorsTheGnomeConstant() {
        // AUTO_HIDE_DELAY_MS = 500 in the GNOME version's ui/constants.ts.
        #expect(PanelAutoHidePolicy.autoHideDelay == 0.5)
    }

    @Test func cursorExitSchedulesTheHideAfterTheGracePeriod() {
        var policy = PanelAutoHidePolicy()
        _ = policy.cursorEntered()

        let effect = policy.cursorExited()

        #expect(effect == .scheduleHide(after: PanelAutoHidePolicy.autoHideDelay))
        #expect(!policy.isPanelHovered)
        #expect(policy.shouldHideWhenHideTimerFires)
    }

    @Test func reEntryCancelsThePendingHide() {
        var policy = PanelAutoHidePolicy()
        _ = policy.cursorEntered()
        _ = policy.cursorExited()

        let effect = policy.cursorEntered()

        #expect(effect == .cancelScheduledHide)
        #expect(policy.isPanelHovered)
    }

    /// A fresh exit after a re-entry restarts the full grace period — the
    /// GNOME `startAutoHideTimeout` clears any existing timeout before
    /// starting a new one, so the schedule effect always carries the full
    /// delay and replaces whatever was pending.
    @Test func reExitRestartsTheFullGracePeriod() {
        var policy = PanelAutoHidePolicy()
        _ = policy.cursorEntered()
        _ = policy.cursorExited()
        _ = policy.cursorEntered()

        let effect = policy.cursorExited()

        #expect(effect == .scheduleHide(after: PanelAutoHidePolicy.autoHideDelay))
    }

    /// The GNOME timeout double-checks the hover state when it fires: a
    /// stale timer that survived a re-entry must not hide a hovered panel.
    @Test func elapsedTimerMustNotHideAHoveredPanel() {
        var policy = PanelAutoHidePolicy()
        _ = policy.cursorExited()
        _ = policy.cursorEntered()

        #expect(!policy.shouldHideWhenHideTimerFires)
    }

    @Test func elapsedTimerHidesWhileTheCursorIsStillOutside() {
        var policy = PanelAutoHidePolicy()
        _ = policy.cursorEntered()
        _ = policy.cursorExited()

        #expect(policy.shouldHideWhenHideTimerFires)
    }

    /// Showing resets the hover state (GNOME `show()` calls
    /// `resetHoverStates()`) and leaves no hide pending, so a panel opened
    /// with the cursor elsewhere stays up until an actual enter/exit cycle
    /// arms the timer — which is what keeps a keyboard-opened,
    /// keyboard-navigated panel alive.
    @Test func showingResetsHoverStateAndCancelsAnyPendingHide() {
        var policy = PanelAutoHidePolicy()
        _ = policy.cursorEntered()

        let effect = policy.panelShown()

        #expect(effect == .cancelScheduledHide)
        #expect(!policy.isPanelHovered)
    }

    /// Hiding (for any reason: Escape, outside click, selection-free
    /// toggle) cancels the pending hide and resets the hover state — the
    /// GNOME `cleanup()`.
    @Test func hidingCancelsThePendingHide() {
        var policy = PanelAutoHidePolicy()
        _ = policy.cursorEntered()
        _ = policy.cursorExited()

        let effect = policy.panelHidden()

        #expect(effect == .cancelScheduledHide)
        #expect(!policy.isPanelHovered)
    }
}
