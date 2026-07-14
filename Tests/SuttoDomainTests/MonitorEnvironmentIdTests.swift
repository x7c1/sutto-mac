import Testing

@testable import SuttoDomain

@Suite struct MonitorEnvironmentIdTests {
    // MARK: - GNOME parity

    /// Values computed by running the GNOME `generateEnvironmentId`
    /// (`operations/monitor/monitor-environment-operations.ts`) on the
    /// same geometry: the port must produce byte-identical keys, including
    /// the DJB2-xor arithmetic, the hex rendering, and the zero padding.
    @Test(arguments: [
        (MonitorFixtures.singleStandard, "0f6dbd0a"),
        (MonitorFixtures.standardWithSecondary, "cb61215e"),
        (MonitorFixtures.laptopOnly, "329dbbdd"),
        (MonitorFixtures.laptopWithUltrawide, "fffe2e78"),
        ([MonitorFixtures.monitor(index: 0, x: 0, y: 0, width: 3440, height: 1440)], "5111b96b"),
        ([], "00001505"),  // hash of the empty string: the DJB2 seed 5381
    ])
    func generatesTheSameKeyAsTheGnomeAlgorithm(monitors: [Monitor], expected: String) {
        #expect(MonitorEnvironmentId.generate(for: monitors) == expected)
    }

    // MARK: - Stability

    /// The same physical setup keys identically no matter the order the
    /// monitors were enumerated in: the algorithm sorts by index first,
    /// the way the GNOME version normalizes its monitor map's iteration
    /// order.
    @Test(arguments: [
        MonitorFixtures.laptopWithUltrawide,
        MonitorFixtures.standardWithSecondary,
        [
            MonitorFixtures.monitor(index: 0, x: 0, y: 0, width: 1920, height: 1080),
            MonitorFixtures.monitor(index: 1, x: -1600, y: 180, width: 1600, height: 900),
            MonitorFixtures.monitor(index: 2, x: 1920, y: -300, width: 2560, height: 1440),
        ],
    ])
    func theKeyDoesNotDependOnEnumerationOrder(monitors: [Monitor]) {
        let reference = MonitorEnvironmentId.generate(for: monitors)

        #expect(MonitorEnvironmentId.generate(for: monitors.reversed()) == reference)
        #expect(MonitorEnvironmentId.generate(for: monitors.shuffled()) == reference)
    }

    /// Only the geometry participates, like the GNOME original: the work
    /// area moves with the Dock and menu bar without the physical setup
    /// changing, and the primary flag is derivable from the arrangement.
    @Test func workAreaAndPrimaryFlagDoNotAffectTheKey() {
        let monitor = MonitorFixtures.monitor(index: 0, x: 0, y: 0, width: 1920, height: 1080)
        let dockShown = Monitor(
            index: 0,
            geometry: monitor.geometry,
            workArea: PixelRect(x: 0, y: 25, width: 1920, height: 955),
            isPrimary: false
        )

        #expect(
            MonitorEnvironmentId.generate(for: [monitor])
                == MonitorEnvironmentId.generate(for: [dockShown]))
    }

    // MARK: - Distinct setups

    /// Every distinct arrangement keys differently: monitor count, relative
    /// position, and resolution all participate. The laptop-only vs
    /// laptop-plus-ultrawide pair is the docking scenario the feature
    /// exists for.
    @Test(arguments: [
        (MonitorFixtures.laptopOnly, MonitorFixtures.laptopWithUltrawide),
        (MonitorFixtures.singleStandard, MonitorFixtures.standardWithSecondary),
        // Same displays, secondary moved from the right to the left.
        (
            MonitorFixtures.standardWithSecondary,
            [
                MonitorFixtures.monitor(index: 0, x: 0, y: 0, width: 1920, height: 1080),
                MonitorFixtures.monitor(index: 1, x: -1600, y: 0, width: 1600, height: 900),
            ]
        ),
        // Same display, resolution changed.
        (
            MonitorFixtures.singleStandard,
            [MonitorFixtures.monitor(index: 0, x: 0, y: 0, width: 2560, height: 1440)]
        ),
    ])
    func differentSetupsGetDifferentKeys(a: [Monitor], b: [Monitor]) {
        #expect(MonitorEnvironmentId.generate(for: a) != MonitorEnvironmentId.generate(for: b))
    }
}
