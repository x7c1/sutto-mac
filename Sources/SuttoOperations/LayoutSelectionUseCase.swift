import SuttoDomain

/// Receives the layout the user picked in the layout panel — together with
/// the display key of the miniature it was clicked on — and routes it to
/// whatever behavior the composition root plugs in.
///
/// This is the seam between the panel and window placement: the composition
/// root injects a handler that snaps the frontmost window onto the clicked
/// display with the selected layout. The UI layer only ever talks to this
/// use case, mirroring how the GNOME panel emits `LayoutSelectedEvent`s to
/// its `LayoutApplicator` without knowing what applying means.
@MainActor
public final class LayoutSelectionUseCase {
    private let handler: (LayoutSelectedEvent) -> Void

    public init(handler: @escaping (LayoutSelectedEvent) -> Void) {
        self.handler = handler
    }

    /// Reports that the user selected a layout in the panel.
    public func select(_ event: LayoutSelectedEvent) {
        handler(event)
    }
}
