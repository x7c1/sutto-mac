import AppKit
import ApplicationServices
import SuttoDomain
import SuttoOperations
import os

/// A window captured through the Accessibility API, wrapping the raw
/// `AXUIElement`. The concrete type stays inside this layer: the operations
/// layer only ever sees it as an opaque ``TargetWindow`` (only
/// ``AXWindowController`` — which created it — unwraps it again).
final class AXTargetWindow: TargetWindow {
    let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }
}

/// Captures and controls a window through the Accessibility (AX) API:
/// `NSWorkspace` names the frontmost app, the AX element tree of that app
/// exposes its focused window, and that window's element is captured once
/// (see ``WindowControlling``) so position and size are read from and
/// written to the same window for the rest of the interaction.
///
/// All frames are in AX coordinates (global top-left origin, y down), as the
/// ``WindowControlling`` protocol requires — the AX attributes use that
/// space natively, so no conversion happens here.
@MainActor
public final class AXWindowController: WindowControlling {
    // The literal values of `kAXFocusedWindowAttribute`,
    // `kAXPositionAttribute`, and `kAXSizeAttribute`. Referencing the
    // globals directly is rejected under Swift 6 strict concurrency (they
    // are imported as shared mutable state), same as in
    // `AccessibilityPermissionChecker`.
    private let focusedWindowAttribute = "AXFocusedWindow" as CFString
    private let positionAttribute = "AXPosition" as CFString
    private let sizeAttribute = "AXSize" as CFString
    private let titleAttribute = "AXTitle" as CFString

    private let logger = Logger(
        subsystem: "io.github.x7c1.SuttoMac", category: "placement")

    public init() {}

    public func captureFocusedWindow() -> TargetWindow? {
        guard let window = focusedWindow() else { return nil }
        return AXTargetWindow(element: window)
    }

    public func identity(of window: TargetWindow) -> WindowIdentity {
        // Bundle identifier from the frontmost application: this is read in
        // the same synchronous step as the capture (see PanelTargetSession),
        // so it names the app that owns the just-captured focused window.
        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if bundleIdentifier == nil {
            logger.notice(
                "frontmost application has no bundle identifier; layout history will skip this window")
        }
        let title = element(of: window).flatMap(title(of:))
        return WindowIdentity(bundleIdentifier: bundleIdentifier, title: title)
    }

    public func frame(of window: TargetWindow) -> PixelRect? {
        guard let element = element(of: window) else { return nil }
        guard let position = position(of: element), let size = size(of: element) else {
            logger.error("could not read the captured window's frame")
            return nil
        }
        return PixelRect(
            x: position.x, y: position.y, width: size.width, height: size.height)
    }

    public func applyFrame(_ frame: PixelRect, to window: TargetWindow) -> Bool {
        guard let element = element(of: window) else { return false }

        let requestedPosition = CGPoint(x: frame.x, y: frame.y)
        let requestedSize = CGSize(width: frame.width, height: frame.height)

        // Set size → position → size, the strategy proven by Rectangle
        // (rxhanson/Rectangle). A single size/position pair can settle on a
        // deviating frame even though every call returns success: resizing
        // can push the window around (menu bar avoidance), and moving can
        // change which screen's constraints apply. Sizing first bounds the
        // window, positioning then anchors the top-left corner, and the
        // final size pass fixes what the move disturbed.
        setSize(requestedSize, of: element)
        setPosition(requestedPosition, of: element)
        setSize(requestedSize, of: element)

        // The AX calls can report success while the app clamps the frame
        // (minimum window sizes, menu bar constraints), so read the frame
        // back and log request versus actual — deviations must be
        // observable in the log, not silent.
        guard let actualPosition = position(of: element), let actualSize = size(of: element) else {
            logger.error("could not read back the frame after applying it")
            return false
        }
        let actual = PixelRect(
            x: actualPosition.x, y: actualPosition.y,
            width: actualSize.width, height: actualSize.height)
        let requested = describe(frame)
        let readBack = describe(actual)
        logger.info(
            """
            placement applied: requested \(requested, privacy: .public), \
            actual \(readBack, privacy: .public)
            """)
        return true
    }

    // MARK: - AX element lookup

    private func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            logger.error("no frontmost application")
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, focusedWindowAttribute, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            let name = app.localizedName ?? "pid \(app.processIdentifier)"
            logger.error(
                """
                no focused window on \(name, privacy: .public) \
                (AXError \(result.rawValue, privacy: .public))
                """)
            return nil
        }
        // Safe: the type id was checked above; AXUIElement has no Swift
        // conditional-cast support, so this is the canonical downcast.
        return (value as! AXUIElement)
    }

    /// Unwraps the AX element from a captured handle. The downcast is safe:
    /// this controller is the only producer of ``TargetWindow`` values, so
    /// every handle it is handed back is an ``AXTargetWindow``.
    private func element(of window: TargetWindow) -> AXUIElement? {
        guard let target = window as? AXTargetWindow else {
            logger.error("target window was not created by this controller")
            return nil
        }
        return target.element
    }

    // MARK: - AX attribute plumbing

    /// The window's `AXTitle`, or `nil` when the attribute cannot be read.
    /// Unlike position/size this is a plain `CFString`, not an `AXValue`, so
    /// it is copied and bridged directly (same read as the e2e AX client).
    private func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, titleAttribute, &value)
        guard result == .success, let title = value as? String else {
            logger.error(
                "could not read the captured window's title (AXError \(result.rawValue, privacy: .public))")
            return nil
        }
        return title
    }

    private func position(of window: AXUIElement) -> CGPoint? {
        var point = CGPoint.zero
        guard axValue(of: window, attribute: positionAttribute, type: .cgPoint, into: &point)
        else { return nil }
        return point
    }

    private func size(of window: AXUIElement) -> CGSize? {
        var size = CGSize.zero
        guard axValue(of: window, attribute: sizeAttribute, type: .cgSize, into: &size)
        else { return nil }
        return size
    }

    private func axValue<T>(
        of window: AXUIElement,
        attribute: CFString,
        type: AXValueType,
        into destination: inout T
    ) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, attribute, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return false
        }
        return AXValueGetValue(value as! AXValue, type, &destination)
    }

    private func setPosition(_ position: CGPoint, of window: AXUIElement) {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return }
        let result = AXUIElementSetAttributeValue(window, positionAttribute, value)
        if result != .success {
            logger.error("setting AXPosition failed (AXError \(result.rawValue, privacy: .public))")
        }
    }

    private func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        let result = AXUIElementSetAttributeValue(window, sizeAttribute, value)
        if result != .success {
            logger.error("setting AXSize failed (AXError \(result.rawValue, privacy: .public))")
        }
    }

    private func describe(_ rect: PixelRect) -> String {
        func format(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }
        return "(x=\(format(rect.x)), y=\(format(rect.y)), "
            + "w=\(format(rect.width)), h=\(format(rect.height)))"
    }
}
