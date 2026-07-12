import SuttoDomain
import os

/// Snaps the frontmost app's focused window to a selected layout.
///
/// The flow: read the focused window's frame → pick its screen (the one
/// containing the window's center; ``SuttoDomain/PlacementFrameResolver``
/// falls back to the mouse's screen, then the primary, when the center is
/// off-screen) → resolve the layout against that screen's work area →
/// apply the resulting AX frame through ``WindowControlling``.
///
/// Every failure mode is logged distinctly and none is fatal: placement is
/// a best-effort operation triggered by a user gesture, so the correct
/// behavior on failure is to do nothing and leave a trace for the
/// developer.
@MainActor
public final class WindowPlacementUseCase {
    private let permission: PermissionChecking
    private let windows: WindowControlling
    private let screens: ScreenProviding
    private let logger = Logger(
        subsystem: "io.github.x7c1.SuttoMac", category: "placement")

    public init(
        permission: PermissionChecking,
        windows: WindowControlling,
        screens: ScreenProviding
    ) {
        self.permission = permission
        self.windows = windows
        self.screens = screens
    }

    /// Places the frontmost app's focused window according to `layout`.
    public func place(_ layout: Layout) {
        guard permission.currentStatus() == .granted else {
            logger.error("placement skipped: accessibility permission not granted")
            return
        }
        let currentScreens = screens.screens()
        guard !currentScreens.isEmpty else {
            logger.error("placement skipped: no screens attached")
            return
        }
        guard let windowFrame = windows.focusedWindowFrame() else {
            logger.error("placement skipped: no focused window on the frontmost app")
            return
        }

        let target: PixelRect?
        do {
            target = try PlacementFrameResolver.resolve(
                layout: layout,
                windowFrame: windowFrame,
                screens: currentScreens,
                mouseLocation: screens.mouseLocation()
            )
        } catch {
            logger.error(
                """
                placement skipped: invalid layout expression in \
                \(layout.label, privacy: .public): \
                \(String(describing: error), privacy: .public)
                """)
            return
        }
        // Non-nil is guaranteed by the isEmpty guard above (resolve only
        // returns nil for an empty screen list), but a screen could detach
        // between the two calls.
        guard let target else {
            logger.error("placement skipped: no screens attached")
            return
        }

        if !windows.applyFrame(target) {
            logger.error("placement failed: could not apply the frame to the focused window")
        }
    }
}
