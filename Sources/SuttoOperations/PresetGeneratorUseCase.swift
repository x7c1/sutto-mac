import SuttoDomain
import os

/// Ensures the generated preset collections exist for the current monitor
/// configuration, persisting any newly generated ones.
///
/// Mirrors `PresetGeneratorOperations` in the GNOME
/// `operations/layout/preset-generator-operations/index.ts` and its
/// `ensurePresetForCurrentMonitors`: for the current monitor count,
/// generate the standard and the wide preset if a preset of that name does
/// not exist yet, and save only when something was added. Existing presets
/// are never regenerated, so their collection/space/layout ids stay stable
/// across launches. The GNOME version calls this when the panel or the
/// preferences open; the mac app does the same (plus once at launch), so a
/// monitor plugged in mid-session is picked up the next time the panel
/// opens.
///
/// The GNOME version prefers a persisted monitor count (its
/// `MonitorCountRepository`, fed by the monitor-environment storage) over
/// live detection; that storage arrives with v0.3 (Monitor Environment),
/// so the mac v0.2 counts the live ``ScreenProviding`` screens directly —
/// the detection fallback of the GNOME implementation.
@MainActor
public final class PresetGeneratorUseCase {
    private let repository: any SpaceCollectionRepository
    private let screens: any ScreenProviding
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "presets")

    public init(repository: any SpaceCollectionRepository, screens: any ScreenProviding) {
        self.repository = repository
        self.screens = screens
    }

    /// Generates and persists the presets missing for the current monitor
    /// count. No monitors (e.g. all displays detached) skips generation,
    /// like the GNOME guard for a zero count.
    public func ensurePresetsForCurrentMonitors() {
        let monitorCount = screens.screens().count
        guard monitorCount > 0 else {
            logger.info("no monitor info available, skipping preset generation")
            return
        }

        var presets = repository.loadPresetCollections()
        var updated = false
        for monitorType in [MonitorType.standard, .wide] {
            let name = PresetGenerator.presetName(
                monitorCount: monitorCount, monitorType: monitorType)
            guard !presets.contains(where: { $0.name == name }) else { continue }

            logger.info("generating preset \"\(name, privacy: .public)\"")
            presets.append(
                PresetGenerator.generate(monitorCount: monitorCount, monitorType: monitorType))
            updated = true
        }

        guard updated else { return }
        do {
            try repository.savePresetCollections(presets)
        } catch {
            // Not fatal: the panel then renders empty until a later ensure
            // succeeds; the GNOME repository swallows save errors with a
            // log line the same way.
            logger.error(
                "failed to save generated presets: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
