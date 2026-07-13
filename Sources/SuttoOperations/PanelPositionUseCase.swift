import SuttoDomain
import os

/// Resolves where the layout panel should open: centered over the
/// frontmost app's focused window, pushed back inside that screen's work
/// area — the GNOME shortcut path (`showAtWindowCenter` +
/// `adjustMainPanelPosition`), whose exact semantics live in
/// ``SuttoDomain/PanelPositionResolver``.
///
/// Returns `nil` when no focused-window frame is readable: no frontmost
/// window, or the Accessibility permission is missing (the AX read fails
/// silently — the permission onboarding is the surface that talks about
/// the permission, not the panel). GNOME *ignores* the shortcut without a
/// focused window; the mac panel deviates deliberately and falls back to
/// its previous behavior — centered on the mouse's screen — because a
/// panel that sometimes does not open reads as a broken shortcut, and the
/// panel is useful for keyboard-driven placement even before a window is
/// focused.
@MainActor
public final class PanelPositionUseCase {
    private let windows: WindowControlling
    private let screens: ScreenProviding
    private let logger = Logger(
        subsystem: "io.github.x7c1.SuttoMac", category: "panel-position")

    public init(windows: WindowControlling, screens: ScreenProviding) {
        self.windows = windows
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
        guard let axWindowFrame = windows.focusedWindowFrame() else {
            logger.debug(
                """
                no focused window frame (no window, or permission missing); \
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
