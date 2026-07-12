import SuttoDomain

/// Registration of system-wide keyboard shortcuts, as required by the
/// operations layer and implemented by the infra layer (Carbon hotkeys).
///
/// Isolated to the main actor because the underlying Carbon event handling
/// runs on the main event loop.
@MainActor
public protocol HotKeyRegistering {
    /// Registers `combo` as a global hotkey and invokes `onPress` every time
    /// it is pressed, regardless of which app is frontmost. The registration
    /// lives as long as the implementing instance.
    ///
    /// Throws if the system refuses the registration (for example, when
    /// another app already claimed the same combo).
    func register(_ combo: KeyCombo, onPress: @escaping @MainActor () -> Void) throws

    /// Removes every registration made through this instance. Used when a
    /// shortcut changes at runtime: unregister the old combo, then
    /// `register` the new one.
    func unregisterAll()
}
