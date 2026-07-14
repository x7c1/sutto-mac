import Foundation
import SuttoDomain
import os

/// Tracks which physical monitor environment the app is running in and
/// keeps the active collection in sync with it: every environment
/// remembers the collection the user last activated there, and switching
/// environments (docking, undocking, plugging a display) restores that
/// environment's choice.
///
/// This merges the GNOME `MonitorEnvironmentOperations`
/// (`operations/monitor/monitor-environment-operations.ts`) with the
/// prefs-sync half of its `MonitorChangeHandler`
/// (`composition/monitor/monitor-change-handler.ts`). GNOME splits the two
/// because its preferences run in a separate process and only meet the
/// extension through GSettings; on macOS the settings window is
/// in-process, so the live selection is always
/// ``PreferencesRepository/activeCollectionId()`` and the ops-held
/// `currentActiveCollectionId` mirror the GNOME handler maintains is
/// unnecessary.
///
/// The environment bookkeeping itself — identity keys, the transition
/// rules, what a switch restores — is the pure
/// ``SuttoDomain/MonitorEnvironmentStorage``; this class adds detection
/// (via ``ScreenProviding``), persistence, and the preference write.
@MainActor
public final class MonitorEnvironmentUseCase {
    private let screens: any ScreenProviding
    private let repository: any MonitorEnvironmentRepository
    private let preferences: any PreferencesRepository
    private let now: () -> Date
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "monitors")

    private var storage = MonitorEnvironmentStorage()
    private var loaded = false

    /// - Parameter now: injected so tests control the timestamps that
    ///   order environments in the rendering lookup.
    public init(
        screens: any ScreenProviding,
        repository: any MonitorEnvironmentRepository,
        preferences: any PreferencesRepository,
        now: @escaping () -> Date = Date.init
    ) {
        self.screens = screens
        self.repository = repository
        self.preferences = preferences
        self.now = now
    }

    /// Detects the current monitors, updates the environment records, and
    /// — when the environment changed — repoints the active collection at
    /// the entered environment's remembered choice (clearing it for an
    /// environment without one, so the panel falls back to the default
    /// preset).
    ///
    /// The composition root calls this once at launch (which also migrates
    /// a pre-existing `activeSpaceCollectionId` into the first detected
    /// environment's record) and again on every screen-parameter change —
    /// the GNOME `detectAndActivate` on enable and on `monitors-changed`.
    ///
    /// - Returns: what happened, so the caller can refresh visible UI on
    ///   a switch.
    @discardableResult
    public func activateEnvironmentForCurrentScreens() -> MonitorEnvironmentStorage.Change {
        loadIfNeeded()
        let monitors = Monitor.monitors(from: screens.screens())
        guard !monitors.isEmpty else {
            // All displays detached (clamshell transitions pass through
            // this): keep the last environment current rather than
            // recording a phantom zero-display environment.
            logger.info("no screens detected, keeping the current environment")
            return .unchanged
        }

        let change = storage.update(
            monitors: monitors,
            activeCollectionId: preferences.activeCollectionId(),
            at: now()
        )
        if case .switched(let restoring) = change {
            preferences.setActiveCollectionId(restoring)
            logger.info(
                """
                environment switched to \(self.storage.currentId, privacy: .public), \
                activating collection: \
                \(restoring?.description ?? "none (default preset)", privacy: .public)
                """)
        }
        persist()
        return change
    }

    /// Records that the user activated `id` in the current environment
    /// (`nil` when the selection was cleared, e.g. by deleting the active
    /// collection), so returning to this environment later restores it.
    /// The caller keeps writing the preference itself; this only maintains
    /// the per-environment memory.
    public func recordActiveCollection(_ id: CollectionId?) {
        loadIfNeeded()
        storage.recordActiveCollection(id, at: now())
        persist()
    }

    /// The stored environments, for the panel's rendering lookup
    /// (``SuttoDomain/PanelDisplayArrangement/resolve(screens:displayCount:environments:)``)
    /// — the macOS counterpart of the environment data behind the GNOME
    /// `getMonitorsForRendering`.
    public func storedEnvironments() -> [MonitorEnvironment] {
        loadIfNeeded()
        return storage.environments
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let stored = repository.load() else {
            logger.info("no environment storage found, starting fresh")
            return
        }
        storage = stored
        logger.info("loaded \(stored.environments.count) monitor environments")
    }

    private func persist() {
        do {
            try repository.save(storage)
        } catch {
            // Not fatal: switching keeps working within this run and the
            // next successful save catches up; the GNOME repository
            // swallows save errors with a log line the same way.
            logger.error(
                "failed to save monitor environments: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
