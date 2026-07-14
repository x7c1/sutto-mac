import SuttoDomain
import os

/// Resolves where the layout panel should open: centered over the window
/// captured for the current opening, pushed back inside that screen's work
/// area — the GNOME shortcut path (`showAtWindowCenter` +
/// `adjustMainPanelPosition`), whose exact semantics live in
/// ``SuttoDomain/PanelPositionResolver``.
///
/// The anchor window comes from ``PanelTargetSession`` — the same window
/// every layout applied during the opening lands on — not from a fresh
/// resolution of the frontmost window, so the panel and the placement can
/// never disagree about which window they are acting on.
///
/// Returns `nil` when no captured-window frame is readable: nothing was
/// captured (no frontmost window, or the Accessibility permission is
/// missing — the AX read fails silently, and the permission onboarding is
/// the surface that talks about the permission, not the panel). GNOME
/// *ignores* the shortcut without a focused window; the mac panel deviates
/// deliberately and falls back to its previous behavior — centered on the
/// mouse's screen — because a panel that sometimes does not open reads as a
/// broken shortcut, and the panel is useful for keyboard-driven placement
/// even before a window is focused.
@MainActor
public final class PanelPositionUseCase {
    private let session: PanelTargetSession
    private let screens: ScreenProviding
    private let logger = Logger(
        subsystem: "io.github.x7c1.SuttoMac", category: "panel-position")

    public init(session: PanelTargetSession, screens: ScreenProviding) {
        self.session = session
        self.screens = screens
    }

    /// The frame the panel should occupy, in AppKit coordinates — ready
    /// for `setFrameOrigin` — or `nil` when the caller should fall back to
    /// mouse-screen centering.
    ///
    /// - Parameters:
    ///   - width: The panel's width in points.
    ///   - height: The panel's height in points.
    public func panelFrame(width: Double, height: Double) -> PixelRect? {
        let allScreens = screens.screens()
        guard let primary = allScreens.first else { return nil }
        guard let axWindowFrame = session.targetFrame() else {
            logger.debug(
                """
                no captured target frame (no window, or permission missing); \
                panel falls back to mouse-screen centering
                """)
            return nil
        }
        let windowFrame = ScreenCoordinateConverter.appKitRect(
            fromAX: axWindowFrame,
            primaryScreenFrame: primary.frame
        )
        return PanelPositionResolver.resolve(
            anchor: windowFrame.center,
            panelWidth: width,
            panelHeight: height,
            screens: allScreens,
            mouseLocation: screens.mouseLocation()
        )
    }
}
