/// One physical display as recorded in a monitor environment: its index,
/// geometry, work area, and whether it is the primary display.
///
/// Mirrors `Monitor` in the GNOME `domain/monitor/types.ts` field for
/// field. Both rectangles are in *top-left-origin* global coordinates
/// (y growing downward) — the coordinate space the GNOME shell uses
/// globally, which macOS reaches through ``ScreenCoordinateConverter``.
/// Storing this space rather than the AppKit one keeps the persisted
/// environment records (and the identity keys hashed from them) in the
/// same orientation as the GNOME version's `monitors.sutto.json`.
public struct Monitor: Equatable, Sendable {
    /// 0-based monitor index; on macOS the position in the
    /// ``…/ScreenProviding`` screen order (primary first).
    public let index: Int

    /// The full frame of the display (top-left origin).
    public let geometry: PixelRect

    /// The frame available to windows — the full frame minus the menu bar
    /// and the Dock (top-left origin). The GNOME counterpart is the shell
    /// work area minus its panels.
    public let workArea: PixelRect

    /// Whether this is the primary display. Always the display at index 0
    /// on macOS (`NSScreen.screens` puts the primary first); kept explicit
    /// for parity with the GNOME record, whose primary can be any index.
    public let isPrimary: Bool

    public init(index: Int, geometry: PixelRect, workArea: PixelRect, isPrimary: Bool) {
        self.index = index
        self.geometry = geometry
        self.workArea = workArea
        self.isPrimary = isPrimary
    }

    /// Converts the current screens (AppKit coordinates, primary first —
    /// the ``…/ScreenProviding`` order) into monitor records, the way the
    /// GNOME `GnomeShellMonitorProvider.detectMonitors` builds its
    /// `Monitor` map from `global.display`.
    public static func monitors(from screens: [Screen]) -> [Monitor] {
        guard let primary = screens.first else { return [] }
        return screens.enumerated().map { index, screen in
            Monitor(
                index: index,
                geometry: ScreenCoordinateConverter.axRect(
                    fromAppKit: screen.frame, primaryScreenFrame: primary.frame),
                workArea: ScreenCoordinateConverter.axRect(
                    fromAppKit: screen.visibleFrame, primaryScreenFrame: primary.frame),
                isPrimary: index == 0
            )
        }
    }
}
