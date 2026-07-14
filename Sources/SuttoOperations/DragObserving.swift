import SuttoDomain

/// Observation of the global left-mouse-drag lifecycle, as required by the
/// operations layer and implemented by the infra layer on top of `NSEvent`
/// global monitors.
///
/// The observer reports *raw* left-drag phases for the whole system — it
/// does not decide whether a given drag is a genuine window move as opposed
/// to text selection or an in-app drag. Correlating a drag with the focused
/// window's frame movement (via ``WindowControlling``) before driving the
/// edge-trigger policy is the orchestration layer's job, not this
/// protocol's.
///
/// Isolated to the main actor because the underlying `NSEvent` monitors fire
/// on the main thread (consistent with ``WindowControlling`` /
/// ``ScreenProviding``).
@MainActor
public protocol DragObserving {
    /// Starts observing, delivering each drag-lifecycle event to `onEvent`.
    /// Calling ``start(onEvent:)`` while already observing is a no-op; call
    /// ``stop()`` first to replace the handler.
    func start(onEvent: @escaping @MainActor (DragEvent) -> Void)

    /// Stops observing. Safe to call when not observing.
    func stop()
}

/// A phase in a left-mouse-drag interaction.
///
/// The pointer is reported in AppKit global coordinates (bottom-left
/// origin, y up) — the same space as ``ScreenProviding``/`NSScreen.frame`,
/// so it lines up with ``SuttoDomain/EdgeTriggerPolicy``'s `screenFrame`.
public enum DragEvent: Equatable, Sendable {
    /// A drag started; carries the pointer at that moment.
    case began(PixelPoint)
    /// The drag continued; carries the current pointer.
    case moved(PixelPoint)
    /// The drag ended (mouse released). The pointer is not reported: the
    /// last ``moved(_:)`` already carried the final position.
    case ended
}
