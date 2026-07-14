import AppKit
import SuttoDomain
import SuttoOperations

/// A ``DragObserving`` built on an `NSEvent` global monitor.
///
/// Global monitors observe events destined for *other* applications, which
/// is exactly what we want here: the user drags some other app's window and
/// we watch that drag from the menu-bar app. We observe `.leftMouseDragged`
/// and `.leftMouseUp`, read the pointer from `NSEvent.mouseLocation` (global,
/// AppKit bottom-left coordinates), and derive the began/moved/ended
/// lifecycle with ``DragPhaseReducer``.
///
/// **Raw phases only — no window-move discrimination.** This monitor cannot
/// tell a genuine window-move drag from an ordinary left-drag (text
/// selection, an in-app drag): it emits raw left-drag phases regardless. The
/// orchestration layer (Operations) correlates a drag with the focused
/// window's frame movement — via ``WindowControlling``/AX — before driving
/// ``SuttoDomain/EdgeTriggerPolicy``. Keep that discrimination out of here.
///
/// **No Accessibility permission required.** A mouse-only `NSEvent` global
/// monitor works without the TCC Accessibility permission. (The app holds AX
/// permission anyway, for window control, but this monitor does not depend on
/// it.) Deliberately no `CGEventTap` — the repo avoids event taps because of
/// their EDR / anti-cheat false-positive footprint; see the rationale in
/// `Sources/SuttoUI/LayoutPanel.swift`.
///
/// Lifecycle mirrors ``ScreenParametersObserver``: install on ``start(onEvent:)``,
/// tear down on ``stop()`` and in `deinit`, guarding against double-install.
@MainActor
public final class NSEventGlobalDragMonitor: DragObserving {
    // nonisolated(unsafe): deinit is nonisolated in Swift 6 and the monitor
    // token must be handed back to NSEvent there. Safe because the token is
    // only mutated on the main actor (start/stop) and read once in deinit.
    private nonisolated(unsafe) var monitor: Any?
    private var reducer = DragPhaseReducer()

    public init() {}

    public func start(onEvent: @escaping @MainActor (DragEvent) -> Void) {
        guard monitor == nil else { return }
        reducer = DragPhaseReducer()
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            // Global monitors are delivered on the main thread; hop through
            // MainActor.assumeIsolated so the compiler knows it too.
            MainActor.assumeIsolated {
                guard let self else { return }
                let phase: DragPhaseReducer.RawPhase =
                    event.type == .leftMouseUp ? .up : .dragged
                let location = NSEvent.mouseLocation
                let point = PixelPoint(x: Double(location.x), y: Double(location.y))
                if let dragEvent = self.reducer.reduce(phase, at: point) {
                    onEvent(dragEvent)
                }
            }
        }
    }

    public func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        reducer = DragPhaseReducer()
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// Derives the ``DragEvent`` began/moved/ended lifecycle from the raw
/// left-mouse phase stream.
///
/// Extracted from ``NSEventGlobalDragMonitor`` so this small piece of state
/// is unit-testable without a live system monitor. The rule is minimal: the
/// first `.dragged` after idle is a drag *began*, each subsequent `.dragged`
/// is a *moved*, and `.up` *ends* the drag and returns to idle so the next
/// drag begins cleanly. A `.up` with no drag in progress (an ordinary click)
/// produces nothing.
struct DragPhaseReducer {
    /// The raw left-mouse phases the monitor observes.
    enum RawPhase {
        case dragged
        case up
    }

    private var isDragging = false

    /// Maps one raw `phase` (at the current `point`) to a drag-lifecycle
    /// event, or `nil` when the phase produces none.
    mutating func reduce(_ phase: RawPhase, at point: PixelPoint) -> DragEvent? {
        switch phase {
        case .dragged:
            if isDragging {
                return .moved(point)
            }
            isDragging = true
            return .began(point)
        case .up:
            guard isDragging else { return nil }
            isDragging = false
            return .ended
        }
    }
}
