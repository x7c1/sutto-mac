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
        let screens = NSScreen.screens.map {
            Screen(frame: pixelRect($0.frame), visibleFrame: pixelRect($0.visibleFrame))
        }
        let mouse = NSEvent.mouseLocation
        guard
            let frame = try PlacementFrameResolver.resolve(
                layout: layout,
                windowFrame: windowFrame,
                screens: screens,
                mouseLocation: PixelPoint(x: mouse.x, y: mouse.y)
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
        let screens = NSScreen.screens.map {
            Screen(frame: pixelRect($0.frame), visibleFrame: pixelRect($0.visibleFrame))
        }
        guard screens.indices.contains(index), let primary = screens.first else {
            throw E2EFailure("no screen at index \(index)")
        }
        return try PlacementFrameResolver.resolve(
            layout: layout,
            on: screens[index],
            primary: primary
        )
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
