import ApplicationServices
import SuttoDomain

/// Test-side Accessibility client: queries another process's AX tree the way
/// any external tool would. Deliberately independent from `SuttoInfra` — the
/// harness observes the app from the outside, so sharing the app's own AX
/// plumbing would let a bug hide by being symmetrical on both sides.
@MainActor
enum AXClient {
    // Literal attribute/role/action names instead of the kAX* globals: the
    // globals are imported as shared mutable state, which Swift 6 strict
    // concurrency rejects (same workaround as in SuttoInfra).
    private static let windowsAttribute = "AXWindows" as CFString
    private static let focusedWindowAttribute = "AXFocusedWindow" as CFString
    private static let positionAttribute = "AXPosition" as CFString
    private static let sizeAttribute = "AXSize" as CFString
    private static let childrenAttribute = "AXChildren" as CFString
    private static let roleAttribute = "AXRole" as CFString
    private static let titleAttribute = "AXTitle" as CFString
    private static let frontmostAttribute = "AXFrontmost" as CFString
    private static let descriptionAttribute = "AXDescription" as CFString
    private static let buttonRole = "AXButton"
    private static let groupRole = "AXGroup"
    private static let pressAction = "AXPress" as CFString

    // MARK: - Application state

    /// Makes the application with the given PID frontmost by setting its
    /// `AXFrontmost` attribute. Modern macOS treats programmatic activation
    /// (`NSApp.activate`, `NSRunningApplication.activate`) from a background
    /// process as advisory and routinely refuses it, but a trusted
    /// Accessibility client may set frontmost directly — which the e2e
    /// runner is, by the suite's own precondition.
    static func makeFrontmost(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        return AXUIElementSetAttributeValue(app, frontmostAttribute, kCFBooleanTrue) == .success
    }

    // MARK: - Windows

    /// All windows of the application with the given PID, in AX order.
    static func windows(ofPID pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        guard let value = copyAttribute(windowsAttribute, of: app),
            CFGetTypeID(value) == CFArrayGetTypeID()
        else { return [] }
        return elements(in: value as! CFArray)
    }

    /// The focused window of the application with the given PID.
    static func focusedWindow(ofPID pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        return element(copyAttribute(focusedWindowAttribute, of: app))
    }

    /// The window's frame in AX coordinates (global top-left origin, y
    /// down), or `nil` when either attribute cannot be read.
    static func frame(of window: AXUIElement) -> PixelRect? {
        guard
            let positionValue = axValue(positionAttribute, of: window),
            let sizeValue = axValue(sizeAttribute, of: window)
        else { return nil }
        // The destinations are concrete C structs (no object references),
        // which is what makes the inout pointer passing safe.
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return PixelRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }

    // MARK: - Groups

    /// Depth-first search for every group labeled `label` in the element's
    /// subtree (the element itself included). NSView accessibility labels
    /// surface as `AXDescription`; the title is checked as a fallback.
    /// The panel's space and display miniatures are such groups
    /// ("Space 1", "Display 2", ...).
    static func groups(labeled label: String, under element: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        if role(of: element) == groupRole,
            description(of: element) == label || title(of: element) == label
        {
            found.append(element)
        }
        for child in children(of: element) {
            found.append(contentsOf: groups(labeled: label, under: child))
        }
        return found
    }

    // MARK: - Buttons

    /// Depth-first search for a button with the given title in the element's
    /// subtree (the element itself included).
    static func button(titled title: String, under element: AXUIElement) -> AXUIElement? {
        if role(of: element) == buttonRole, self.title(of: element) == title {
            return element
        }
        for child in children(of: element) {
            if let found = button(titled: title, under: child) {
                return found
            }
        }
        return nil
    }

    /// Presses the element (`AXPress`), i.e. clicks a button without
    /// synthesizing mouse events.
    static func press(_ element: AXUIElement) throws {
        let result = AXUIElementPerformAction(element, pressAction)
        guard result == .success else {
            throw E2EFailure("AXPress failed (AXError \(result.rawValue))")
        }
    }

    // MARK: - Attribute plumbing

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(childrenAttribute, of: element),
            CFGetTypeID(value) == CFArrayGetTypeID()
        else { return [] }
        return elements(in: value as! CFArray)
    }

    private static func role(of element: AXUIElement) -> String? {
        copyAttribute(roleAttribute, of: element) as? String
    }

    private static func title(of element: AXUIElement) -> String? {
        copyAttribute(titleAttribute, of: element) as? String
    }

    private static func description(of element: AXUIElement) -> String? {
        copyAttribute(descriptionAttribute, of: element) as? String
    }

    private static func copyAttribute(
        _ attribute: CFString, of element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func axValue(
        _ attribute: CFString, of element: AXUIElement
    ) -> AXValue? {
        guard let value = copyAttribute(attribute, of: element),
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // Safe: the type id was checked above (see `element(_:)`).
        return (value as! AXValue)
    }

    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Safe: the type id was checked above; AXUIElement has no Swift
        // conditional-cast support, so this is the canonical downcast.
        return (value as! AXUIElement)
    }

    private static func elements(in array: CFArray) -> [AXUIElement] {
        (array as [AnyObject]).compactMap { element($0) }
    }
}
