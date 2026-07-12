import SuttoDomain
import os

/// Snaps the frontmost app's focused window to a selected layout.
///
/// Two placement rules coexist:
///
/// - ``place(_:)`` — the window's *own* screen: read the focused window's
///   frame → pick its screen (the one containing the window's center;
///   ``SuttoDomain/PlacementFrameResolver`` falls back to the mouse's
///   screen, then the primary, when the center is off-screen) → resolve
///   the layout against that screen's work area.
/// - ``place(_:onDisplayKey:)`` — an explicitly *chosen* screen: the panel
///   passes the display key of the miniature the user clicked, and the
///   window lands on that screen no matter where it currently is. This is
///   the GNOME `LayoutApplicator` flow, which resolves the event's monitor
///   key to a monitor and skips placement when no such monitor exists.
///
/// Display keys map to screens by index — key `"N"` is the N-th screen of
/// ``ScreenProviding``'s order; see ``SuttoDomain/PanelDisplayKey``.
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

    /// Places the frontmost app's focused window according to `layout`, on
    /// the screen the window currently belongs to.
    public func place(_ layout: Layout) {
        guard let context = placementContext() else { return }

        resolveAndApply(layout) { () throws(LayoutExpressionParseError) -> PixelRect? in
            try PlacementFrameResolver.resolve(
                layout: layout,
                windowFrame: context.windowFrame,
                screens: context.screens,
                mouseLocation: screens.mouseLocation()
            )
        }
    }

    /// Places the frontmost app's focused window according to `layout`, on
    /// the screen the display key names.
    ///
    /// When the key resolves to no connected screen — a collection made
    /// for more displays than are attached, or a malformed key in
    /// hand-edited JSON — placement is skipped with a log, exactly like
    /// the GNOME `LayoutApplicator` when `getMonitorByKey` finds nothing.
    /// (The panel already renders such displays non-clickable, so this is
    /// a second line of defense.)
    public func place(_ layout: Layout, onDisplayKey key: String) {
        guard let context = placementContext() else { return }

        guard
            let index = PanelDisplayKey.screenIndex(for: key),
            context.screens.indices.contains(index)
        else {
            logger.error(
                """
                placement skipped: no screen for display key \
                \(key, privacy: .public) \
                (\(context.screens.count) connected)
                """)
            return
        }

        resolveAndApply(layout) { () throws(LayoutExpressionParseError) -> PixelRect? in
            try PlacementFrameResolver.resolve(
                layout: layout,
                on: context.screens[index],
                // Non-nil: placementContext() guarantees screens is
                // non-empty.
                primary: context.screens[0]
            )
        }
    }

    // MARK: - Shared plumbing

    private struct PlacementContext {
        let screens: [Screen]
        let windowFrame: PixelRect
    }

    /// The guards every placement path shares: permission, at least one
    /// screen, and a focused window to move.
    private func placementContext() -> PlacementContext? {
        guard permission.currentStatus() == .granted else {
            logger.error("placement skipped: accessibility permission not granted")
            return nil
        }
        let currentScreens = screens.screens()
        guard !currentScreens.isEmpty else {
            logger.error("placement skipped: no screens attached")
            return nil
        }
        guard let windowFrame = windows.focusedWindowFrame() else {
            logger.error("placement skipped: no focused window on the frontmost app")
            return nil
        }
        return PlacementContext(screens: currentScreens, windowFrame: windowFrame)
    }

    private func resolveAndApply(
        _ layout: Layout,
        resolve: () throws(LayoutExpressionParseError) -> PixelRect?
    ) {
        let target: PixelRect?
        do {
            target = try resolve()
        } catch {
            logger.error(
                """
                placement skipped: invalid layout expression in \
                \(layout.label, privacy: .public): \
                \(String(describing: error), privacy: .public)
                """)
            return
        }
        // Only the window's-own-screen resolver can return nil (empty
        // screen list); the context guard makes that unreachable unless a
        // screen detaches between the two calls.
        guard let target else {
            logger.error("placement skipped: no screens attached")
            return
        }

        if !windows.applyFrame(target) {
            logger.error("placement failed: could not apply the frame to the focused window")
        }
    }
}
