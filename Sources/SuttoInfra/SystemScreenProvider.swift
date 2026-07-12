import AppKit
import SuttoDomain
import SuttoOperations

/// Bridges `NSScreen` and `NSEvent.mouseLocation` to the domain's value
/// types. `NSScreen.screens` already puts the primary screen (the one whose
/// bottom-left corner is the global AppKit origin) first, which is exactly
/// the order ``ScreenProviding`` requires.
@MainActor
public struct SystemScreenProvider: ScreenProviding {
    public init() {}

    public func screens() -> [Screen] {
        NSScreen.screens.map { screen in
            Screen(
                frame: pixelRect(from: screen.frame),
                visibleFrame: pixelRect(from: screen.visibleFrame)
            )
        }
    }

    public func mouseLocation() -> PixelPoint {
        let location = NSEvent.mouseLocation
        return PixelPoint(x: location.x, y: location.y)
    }

    private func pixelRect(from rect: NSRect) -> PixelRect {
        PixelRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }
}
