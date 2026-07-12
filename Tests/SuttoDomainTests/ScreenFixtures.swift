@testable import SuttoDomain

/// Multi-monitor arrangements shared by the coordinate-conversion and
/// placement tests. All frames are in AppKit coordinates (origin at the
/// bottom-left of the primary screen, y up).
///
/// The primary screen is 1920x1080 with a 25 px menu bar, so its work area
/// is 1920x1055 with the origin unchanged (the menu bar sits at the top,
/// which in AppKit coordinates trims the *high*-y side). Secondary screens
/// are 1600x900 with their own 25 px menu bar (every display has one when
/// "Displays have separate Spaces" is on), so their work areas are 1600x875.
enum ScreenFixtures {
    static let primary = Screen(
        frame: PixelRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: PixelRect(x: 0, y: 0, width: 1920, height: 1055)
    )

    static func secondary(x: Double, y: Double) -> Screen {
        Screen(
            frame: PixelRect(x: x, y: y, width: 1600, height: 900),
            visibleFrame: PixelRect(x: x, y: y, width: 1600, height: 875)
        )
    }

    /// A single primary screen.
    static let single = [primary]

    /// Secondary to the right of the primary, bottom edges aligned.
    static let secondaryRight = [primary, secondary(x: 1920, y: 0)]

    /// Secondary to the left of the primary: negative x.
    static let secondaryLeft = [primary, secondary(x: -1600, y: 0)]

    /// Secondary stacked above the primary: larger y in AppKit coordinates.
    static let stackedAbove = [primary, secondary(x: 0, y: 1080)]

    /// Secondary stacked below the primary: negative y.
    static let stackedBelow = [primary, secondary(x: 0, y: -900)]

    /// Secondary below *and* left of the primary: both coordinates negative.
    static let belowAndLeft = [primary, secondary(x: -1600, y: -900)]

    static let allConfigurations: [[Screen]] = [
        single, secondaryRight, secondaryLeft, stackedAbove, stackedBelow, belowAndLeft,
    ]
}
