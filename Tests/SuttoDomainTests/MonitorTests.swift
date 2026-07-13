import Testing

@testable import SuttoDomain

/// ``Monitor/monitors(from:)``: the conversion from AppKit screens to the
/// top-left-origin monitor records the environment storage keeps.
@Suite struct MonitorTests {
    @Test func convertsASingleScreenToTopLeftCoordinates() {
        let monitors = Monitor.monitors(from: ScreenFixtures.single)

        #expect(
            monitors == [
                Monitor(
                    index: 0,
                    geometry: PixelRect(x: 0, y: 0, width: 1920, height: 1080),
                    // The AppKit work area trims the high-y side (menu bar
                    // at the top); flipped, the top-left y moves down by
                    // the menu bar height.
                    workArea: PixelRect(x: 0, y: 25, width: 1920, height: 1055),
                    isPrimary: true
                )
            ])
    }

    /// A bottom-aligned secondary in AppKit space (y = 0) is bottom-aligned
    /// in the flipped space too: its top edge sits below the primary's.
    @Test func convertsASecondaryRelativeToThePrimary() {
        let monitors = Monitor.monitors(from: ScreenFixtures.secondaryRight)

        #expect(monitors.count == 2)
        #expect(monitors[1].index == 1)
        #expect(monitors[1].isPrimary == false)
        #expect(monitors[1].geometry == PixelRect(x: 1920, y: 180, width: 1600, height: 900))
    }

    /// Indices follow the screen order (primary first), which is what the
    /// display keys of the collections refer to.
    @Test(arguments: ScreenFixtures.allConfigurations)
    func indexesFollowTheScreenOrder(screens: [Screen]) {
        let monitors = Monitor.monitors(from: screens)

        #expect(monitors.map(\.index) == Array(0..<screens.count))
        #expect(monitors.map(\.isPrimary) == screens.indices.map { $0 == 0 })
    }

    @Test func noScreensYieldNoMonitors() {
        #expect(Monitor.monitors(from: []) == [])
    }
}
