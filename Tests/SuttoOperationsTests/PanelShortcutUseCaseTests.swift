import SuttoDomain
import Testing

@testable import SuttoOperations

/// ``HotKeyRegistering`` stub tracking the live registrations, with
/// scriptable per-combo failures to simulate the system refusing a combo.
@MainActor
private final class RecordingHotKeyRegistrar: HotKeyRegistering {
    private(set) var registeredCombos: [KeyCombo] = []
    private(set) var handlers: [@MainActor () -> Void] = []
    var failingCombos: [KeyCombo] = []

    func register(_ combo: KeyCombo, onPress: @escaping @MainActor () -> Void) throws {
        if failingCombos.contains(combo) {
            throw StubError(message: "combo already taken")
        }
        registeredCombos.append(combo)
        handlers.append(onPress)
    }

    func unregisterAll() {
        registeredCombos = []
        handlers = []
    }
}

@Suite @MainActor struct PanelShortcutUseCaseTests {
    private let preferences = InMemoryPreferencesRepository()
    private let registrar = RecordingHotKeyRegistrar()

    private final class PressCounter {
        var count = 0
    }

    private let presses = PressCounter()

    private var useCase: PanelShortcutUseCase {
        PanelShortcutUseCase(preferences: preferences, registrar: registrar) {
            [presses] in presses.count += 1
        }
    }

    private let customCombo = KeyCombo(keyCode: 40, modifiers: [.control, .command])  // ⌃⌘K

    // MARK: - Resolution

    @Test func fallsBackToTheDefaultComboWhenNothingIsStored() {
        #expect(useCase.currentCombo() == .defaultTogglePanel)
        #expect(useCase.isDefault())
    }

    @Test func usesTheStoredComboWhenPresent() {
        preferences.storedPanelToggleShortcut = customCombo

        #expect(useCase.currentCombo() == customCombo)
        #expect(!useCase.isDefault())
    }

    // MARK: - Launch registration

    @Test func registersTheEffectiveComboAtLaunch() throws {
        preferences.storedPanelToggleShortcut = customCombo

        try useCase.registerCurrent()

        #expect(registrar.registeredCombos == [customCombo])
    }

    // MARK: - Live update

    @Test func updateSwitchesTheLiveRegistration() throws {
        let useCase = useCase
        try useCase.registerCurrent()

        try useCase.update(to: customCombo)

        #expect(registrar.registeredCombos == [customCombo])
        #expect(preferences.storedPanelToggleShortcut == customCombo)
    }

    /// The new registration must answer presses — re-registering with a
    /// dead handler would leave a shortcut that looks bound but does
    /// nothing.
    @Test func theNewRegistrationStillTogglesThePanel() throws {
        let useCase = useCase
        try useCase.registerCurrent()

        try useCase.update(to: customCombo)
        registrar.handlers.forEach { $0() }

        #expect(presses.count == 1)
    }

    /// Capturing the default combo stores nothing — the default is the
    /// absence of a stored value, so a later change of the built-in
    /// default reaches users who never picked their own.
    @Test func updatingToTheDefaultClearsTheStoredValue() throws {
        preferences.storedPanelToggleShortcut = customCombo
        let useCase = useCase
        try useCase.registerCurrent()

        try useCase.update(to: .defaultTogglePanel)

        #expect(preferences.storedPanelToggleShortcut == nil)
        #expect(registrar.registeredCombos == [.defaultTogglePanel])
    }

    @Test func updatingToTheCurrentComboIsANoOp() throws {
        let useCase = useCase
        try useCase.registerCurrent()

        try useCase.update(to: .defaultTogglePanel)

        // Still the single launch registration; nothing re-registered.
        #expect(registrar.registeredCombos == [.defaultTogglePanel])
    }

    /// When the system refuses the new combo, the old one is restored and
    /// nothing is persisted — the running shortcut is never lost.
    @Test func aRefusedComboRestoresThePreviousRegistration() throws {
        let useCase = useCase
        try useCase.registerCurrent()
        registrar.failingCombos = [customCombo]

        #expect(throws: StubError.self) {
            try useCase.update(to: customCombo)
        }
        #expect(registrar.registeredCombos == [.defaultTogglePanel])
        #expect(preferences.storedPanelToggleShortcut == nil)
    }

    // MARK: - Reset

    @Test func resetRestoresTheDefaultLiveAndPersisted() throws {
        preferences.storedPanelToggleShortcut = customCombo
        let useCase = useCase
        try useCase.registerCurrent()

        try useCase.resetToDefault()

        #expect(registrar.registeredCombos == [.defaultTogglePanel])
        #expect(preferences.storedPanelToggleShortcut == nil)
        #expect(useCase.isDefault())
    }
}
