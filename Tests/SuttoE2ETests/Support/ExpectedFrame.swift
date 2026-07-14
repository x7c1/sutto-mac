import AppKit
import SuttoDomain

/// Computes the frame the scenario expects a snapped window to land on,
/// using the same domain resolver the app uses, fed with the test process's
/// own reading of the actual screens (mirroring what
/// `SuttoInfra.SystemScreenProvider` feeds the app, without importing it).
@MainActor
enum ExpectedFrame {
    /// The target frame in AX coordinates for `layout` applied to a window
    /// currently at `windowFrame` (AX coordinates).
    static func resolve(_ layout: Layout, windowFrame: PixelRect) throws -> PixelRect {
        let screens = currentScreens()
        guard
            let frame = try PlacementFrameResolver.resolve(
                layout: layout,
                windowFrame: windowFrame,
                screens: screens
            )
        else {
            throw E2EFailure("no screens attached")
        }
        return frame
    }

    /// The target frame in AX coordinates for `layout` applied on the
    /// screen at `index` of `NSScreen.screens` — the explicit-screen rule
    /// behind cross-monitor placement (display key "N" names screen N).
    static func resolve(_ layout: Layout, onScreenAt index: Int) throws -> PixelRect {
        let screens = currentScreens()
        guard screens.indices.contains(index), let primary = screens.first else {
            throw E2EFailure("no screen at index \(index)")
        }
        return try PlacementFrameResolver.resolve(
            layout: layout,
            on: screens[index],
            primary: primary
        )
    }

    /// The screens as the app under test sees them. A bare test-runner
    /// process reports secondary screens' `visibleFrame` *without* their
    /// menu bar (observed: a secondary's visible height came back 30 pt
    /// too tall, so the cross-monitor expectation missed by exactly the
    /// menu bar); `NSApplication.finishLaunching()` is what switches
    /// AppKit to the fully-informed reporting a real app gets. `.prohibited`
    /// keeps the runner invisible (no Dock icon, no activation).
    private static var appKitLaunched = false

    /// Exposed for scenarios that replicate the app's domain math beyond a
    /// single frame — the keyboard scenario rebuilds the whole panel model
    /// from these screens to predict where the focus travels.
    static func currentScreens() -> [Screen] {
        if !appKitLaunched {
            appKitLaunched = true
            NSApplication.shared.setActivationPolicy(.prohibited)
            NSApplication.shared.finishLaunching()
        }
        return NSScreen.screens.map {
            Screen(frame: pixelRect($0.frame), visibleFrame: pixelRect($0.visibleFrame))
        }
    }

    private static func pixelRect(_ rect: NSRect) -> PixelRect {
        PixelRect(
            x: rect.origin.x, y: rect.origin.y,
            width: rect.size.width, height: rect.size.height)
    }
}

extension PixelRect {
    /// Component-wise comparison with a symmetric tolerance, for asserting
    /// AX read-back frames against computed ones.
    func isApproximately(_ other: PixelRect, tolerance: Double) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
