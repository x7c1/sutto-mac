@testable import SuttoDomain

/// Monitor records shared by the monitor-environment tests. All geometry
/// is in the top-left-origin space ``Monitor`` documents.
enum MonitorFixtures {
    static func monitor(
        index: Int, x: Double, y: Double, width: Double, height: Double,
        menuBar: Double = 25
    ) -> Monitor {
        Monitor(
            index: index,
            geometry: PixelRect(x: x, y: y, width: width, height: height),
            workArea: PixelRect(
                x: x, y: y + menuBar, width: width, height: height - menuBar),
            isPrimary: index == 0
        )
    }

    /// The development machine's laptop display alone (MacBook Pro 14",
    /// 1512×982 points).
    static let laptopOnly = [
        monitor(index: 0, x: 0, y: 0, width: 1512, height: 982)
    ]

    /// The development machine at the desk: laptop plus an ultrawide
    /// (3440×1440) to its right.
    static let laptopWithUltrawide = [
        monitor(index: 0, x: 0, y: 0, width: 1512, height: 982),
        monitor(index: 1, x: 1512, y: 0, width: 3440, height: 1440),
    ]

    /// A 1920×1080 primary alone.
    static let singleStandard = [
        monitor(index: 0, x: 0, y: 0, width: 1920, height: 1080)
    ]

    /// A 1920×1080 primary with a 1600×900 secondary to its right.
    static let standardWithSecondary = [
        monitor(index: 0, x: 0, y: 0, width: 1920, height: 1080),
        monitor(index: 1, x: 1920, y: 0, width: 1600, height: 900),
    ]
}
