import Carbon.HIToolbox
import SuttoDomain
import SuttoOperations

/// Registers system-wide keyboard shortcuts through the Carbon hotkey APIs
/// (`RegisterEventHotKey`), implementing ``HotKeyRegistering``.
///
/// Carbon hotkeys are the standard mechanism for global shortcuts in macOS
/// apps: unlike a CGEvent tap they require no Accessibility permission, and
/// the events are delivered only when the registered combo is pressed, no
/// matter which app is frontmost.
@MainActor
public final class CarbonHotKeyRegistrar: HotKeyRegistering {
    private var hotKeys: [CarbonHotKey] = []

    public init() {}

    public func register(_ combo: KeyCombo, onPress: @escaping @MainActor () -> Void) throws {
        // IDs only need to be unique within this registrar; the signature in
        // EventHotKeyID already namespaces them to Sutto.
        let id = UInt32(hotKeys.count + 1)
        hotKeys.append(try CarbonHotKey(combo: combo, id: id, onPress: onPress))
    }
}

/// A Carbon hotkey API call failed with the given `OSStatus`. The most
/// likely value in practice is -9878 (`eventHotKeyExistsErr`): another app
/// already registered the same combo.
public struct CarbonHotKeyError: Error, CustomStringConvertible {
    public let operation: String
    public let status: OSStatus

    public var description: String {
        "\(operation) failed with OSStatus \(status)"
    }
}

/// One registered Carbon hotkey: alive while the instance is alive,
/// unregistered on deinit.
///
/// Each instance installs its own Carbon event handler with `self` as the
/// handler's context pointer, so the C callback can bridge straight back to
/// the owning instance without a global lookup table. Every handler on the
/// dispatcher target sees every hotkey press, so the callback matches the
/// event's `EventHotKeyID` against its own and passes foreign ones on.
@MainActor
private final class CarbonHotKey {
    private let identity: EventHotKeyID
    private let onPress: @MainActor () -> Void

    // nonisolated(unsafe): deinit is nonisolated in Swift 6 and may not read
    // main-actor state, but it must release these Carbon refs. This is safe
    // because the refs are only written in init and read in deinit, which
    // by definition runs after every other access to the instance.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandlerRef: EventHandlerRef?

    init(combo: KeyCombo, id: UInt32, onPress: @escaping @MainActor () -> Void) throws {
        identity = EventHotKeyID(signature: Self.signature, id: id)
        self.onPress = onPress

        var pressed = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // passUnretained: the handler must not keep self alive, or deinit
        // (which removes the handler) could never run. The reverse dangling
        // risk does not exist because deinit removes the handler first.
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &pressed,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            throw CarbonHotKeyError(operation: "InstallEventHandler", status: installStatus)
        }

        var registered: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.modifiers.carbonFlags,
            identity,
            GetEventDispatcherTarget(),
            0,
            &registered
        )
        guard registerStatus == noErr, let registered else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            throw CarbonHotKeyError(operation: "RegisterEventHotKey", status: registerStatus)
        }
        hotKeyRef = registered
    }

    deinit {
        // Remove the handler before unregistering so no event can arrive
        // in between and bridge to a half-torn-down instance.
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    /// Called from the C event handler with the ID of the pressed hotkey.
    /// Declines events for other hotkeys so their own handlers can run.
    func handlePress(of pressedID: EventHotKeyID) -> OSStatus {
        guard pressedID.signature == identity.signature, pressedID.id == identity.id else {
            return OSStatus(eventNotHandledErr)
        }
        onPress()
        return noErr
    }

    /// Four-char code "Suto", marking EventHotKeyIDs as belonging to Sutto.
    private static let signature: OSType = "Suto".unicodeScalars.reduce(0) { code, scalar in
        (code << 8) | OSType(scalar.value)
    }
}

/// The C callback bridging Carbon back into Swift: recovers the CarbonHotKey
/// instance from the context pointer and forwards the pressed hotkey's ID.
///
/// A `@convention(c)` function cannot capture context, which is why the
/// instance travels through `userData` as an unretained opaque pointer.
private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    var pressedID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedID
    )
    guard status == noErr else { return status }

    let hotKey = Unmanaged<CarbonHotKey>.fromOpaque(userData).takeUnretainedValue()
    // Carbon dispatches hotkey events on the main thread, so hopping onto
    // the main actor is an assertion, not a switch.
    return MainActor.assumeIsolated {
        hotKey.handlePress(of: pressedID)
    }
}

extension KeyCombo.Modifiers {
    /// The Carbon modifier mask corresponding to this modifier set.
    fileprivate var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }
}
