import SuttoDomain

/// Receives the layout the user picked in the layout panel and routes it to
/// whatever behavior the composition root plugs in.
///
/// This is the seam for the window-placement work: in v0.1 the injected
/// handler only logs the selection, and the placement PR swaps it for a
/// handler that snaps the frontmost window to the selected layout. The UI
/// layer only ever talks to this use case, so that swap does not touch
/// panel code.
@MainActor
public final class LayoutSelectionUseCase {
    private let handler: (Layout) -> Void

    public init(handler: @escaping (Layout) -> Void) {
        self.handler = handler
    }

    /// Reports that the user selected `layout` in the panel.
    public func select(_ layout: Layout) {
        handler(layout)
    }
}
