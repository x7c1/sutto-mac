import Testing

@testable import SuttoDomain

/// The default-preset rule: which generated preset stands in when the user
/// has not selected a collection. Classification is only this default —
/// explicit selection (settings) always wins over it.
@Suite struct PresetSelectionTests {
    private let presets = [
        PresetGenerator.generate(monitorCount: 1, monitorType: .standard),
        PresetGenerator.generate(monitorCount: 1, monitorType: .wide),
        PresetGenerator.generate(monitorCount: 2, monitorType: .standard),
        PresetGenerator.generate(monitorCount: 2, monitorType: .wide),
    ]

    private func screen(width: Double, height: Double) -> Screen {
        Screen(
            frame: PixelRect(x: 0, y: 0, width: width, height: height),
            visibleFrame: PixelRect(x: 0, y: 25, width: width, height: height - 25)
        )
    }

    @Test func picksTheStandardPresetForAStandardPrimary() {
        let preset = PresetSelection.defaultPreset(
            in: presets, screens: [screen(width: 1920, height: 1080)])

        #expect(preset?.name == "1 Monitor - Standard")
    }

    @Test func picksTheWidePresetForAnUltrawidePrimary() {
        let preset = PresetSelection.defaultPreset(
            in: presets, screens: [screen(width: 3440, height: 1440)])

        #expect(preset?.name == "1 Monitor - Wide")
    }

    /// The classification keys off the primary (first) screen: a standard
    /// laptop primary with an ultrawide secondary defaults to the standard
    /// preset for the pair — selecting the wide one is what the settings
    /// list is for.
    @Test func classifiesByThePrimaryScreen() {
        let preset = PresetSelection.defaultPreset(
            in: presets,
            screens: [
                screen(width: 1800, height: 1169),
                screen(width: 3840, height: 1620),
            ])

        #expect(preset?.name == "2 Monitors - Standard")
    }

    /// No preset named for the arrangement (a third monitor arrived and no
    /// ensure ran yet): the first stored preset stands in — the GNOME
    /// `presets[0]` fallback.
    @Test func fallsBackToTheFirstPresetWhenNoNameMatches() {
        let preset = PresetSelection.defaultPreset(
            in: presets,
            screens: [
                screen(width: 1920, height: 1080),
                screen(width: 1920, height: 1080),
                screen(width: 1920, height: 1080),
            ])

        #expect(preset?.name == "1 Monitor - Standard")
    }

    @Test func fallsBackToTheFirstPresetWithoutScreens() {
        let preset = PresetSelection.defaultPreset(in: presets, screens: [])

        #expect(preset?.name == "1 Monitor - Standard")
    }

    @Test func isNilWithoutStoredPresets() {
        let preset = PresetSelection.defaultPreset(
            in: [], screens: [screen(width: 1920, height: 1080)])

        #expect(preset == nil)
    }
}
