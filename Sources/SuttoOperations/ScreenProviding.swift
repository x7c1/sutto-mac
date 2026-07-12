import SuttoDomain

/// The current display arrangement, as required by the operations layer and
/// implemented by the infra layer on top of `NSScreen`.
///
/// Isolated to the main actor because `NSScreen` is main-thread bound.
@MainActor
public protocol ScreenProviding {
    /// The current screens in AppKit coordinates, ordered like
    /// `NSScreen.screens`: the first element is the primary screen (the one
    /// whose bottom-left corner is the global AppKit origin). Empty when no
    /// display is attached.
    func screens() -> [Screen]

    /// The mouse pointer location in AppKit coordinates.
    func mouseLocation() -> PixelPoint
}
