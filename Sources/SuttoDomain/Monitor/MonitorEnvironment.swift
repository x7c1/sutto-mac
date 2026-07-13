import Foundation

/// One remembered monitor environment: a physical display setup the app
/// has seen, identified by ``MonitorEnvironmentId``, together with the
/// monitor geometries it had when last seen and the collection the user
/// last activated in it.
///
/// Mirrors `MonitorEnvironment` in the GNOME `domain/monitor/types.ts`.
public struct MonitorEnvironment: Equatable, Sendable {
    /// The identity key, from ``MonitorEnvironmentId/generate(for:)``.
    public let id: String

    /// The monitors as of the last time this environment was current.
    /// Real geometry, not synthesized — this is what lets the panel render
    /// a collection made for a detached setup in that setup's true
    /// arrangement.
    public var monitors: [Monitor]

    /// The collection the user last activated while this environment was
    /// current; `nil` when none was ever chosen here.
    public var lastActiveCollectionId: CollectionId?

    /// When this environment was last current (or last had its collection
    /// recorded); newer environments win the rendering lookup of
    /// ``PanelDisplayArrangement/resolve(screens:displayCount:environments:)``.
    public var lastActiveAt: Date

    public init(
        id: String, monitors: [Monitor], lastActiveCollectionId: CollectionId?,
        lastActiveAt: Date
    ) {
        self.id = id
        self.monitors = monitors
        self.lastActiveCollectionId = lastActiveCollectionId
        self.lastActiveAt = lastActiveAt
    }
}

/// Every monitor environment the app has seen, plus which one is current —
/// and the transition rules between them.
///
/// The data shape mirrors `MonitorEnvironmentStorage` in the GNOME
/// `domain/monitor/types.ts`; the transition logic in ``update(monitors:activeCollectionId:at:)``
/// ports `detectAndSaveMonitors` of the GNOME
/// `MonitorEnvironmentOperations` as a pure function, so the environment
/// bookkeeping — the core of monitor-environment switching — is testable
/// without any storage or AppKit involved.
public struct MonitorEnvironmentStorage: Equatable, Sendable {
    /// What a detection pass concluded, for the caller to act on.
    public enum Change: Equatable, Sendable {
        /// Same environment as before (or the very first detection):
        /// nothing to activate.
        case unchanged

        /// The physical setup changed. `restoring` carries the collection
        /// the user last activated in the environment just entered — `nil`
        /// when the environment is new or never had a selection, in which
        /// case the caller clears the active selection so the panel falls
        /// back to the default preset. (The GNOME handler leaves the old
        /// collection active in that case; clearing instead matches this
        /// app's existing "fall back to the fitting preset rather than pin
        /// a selection the user never made" behavior — see
        /// `CollectionSettingsUseCase.deleteCollection`.)
        case switched(restoring: CollectionId?)
    }

    /// Every environment seen so far, in first-seen order.
    public var environments: [MonitorEnvironment]

    /// The ``MonitorEnvironment/id`` of the current environment; empty
    /// before the first detection, like the GNOME `current: ''`.
    public var currentId: String

    public init(environments: [MonitorEnvironment] = [], currentId: String = "") {
        self.environments = environments
        self.currentId = currentId
    }

    /// The current environment's record, if any.
    public var currentEnvironment: MonitorEnvironment? {
        environments.first { $0.id == currentId }
    }

    /// Records a detection pass: the port of the GNOME
    /// `detectAndSaveMonitors`, minus the I/O.
    ///
    /// - A known environment gets its monitor geometries and timestamp
    ///   refreshed; re-detecting the *same* environment also back-fills
    ///   `activeCollectionId` (the caller's live selection) into its
    ///   record, like the GNOME `currentActiveCollectionId` write-back.
    /// - Entering a *different* known environment reports
    ///   `.switched(restoring:)` with that environment's remembered
    ///   collection.
    /// - An unseen environment is added. On the first detection ever
    ///   (`currentId` empty) it inherits `activeCollectionId` — this is
    ///   the migration of the pre-existing single `activeSpaceCollectionId`
    ///   preference into the current environment's entry. Reached by a
    ///   *switch*, it starts with no selection instead, so the caller
    ///   falls back to the default preset rather than inheriting the
    ///   previous environment's choice.
    ///
    /// - Parameters:
    ///   - monitors: the detected monitors, from ``Monitor/monitors(from:)``.
    ///   - activeCollectionId: the selection active right now (the stored
    ///     preference), or `nil` when none.
    ///   - now: the detection timestamp.
    public mutating func update(
        monitors: [Monitor], activeCollectionId: CollectionId?, at now: Date
    ) -> Change {
        let environmentId = MonitorEnvironmentId.generate(for: monitors)
        let switched = !currentId.isEmpty && currentId != environmentId
        defer { currentId = environmentId }

        if let index = environments.firstIndex(where: { $0.id == environmentId }) {
            environments[index].monitors = monitors
            environments[index].lastActiveAt = now
            if switched {
                return .switched(restoring: environments[index].lastActiveCollectionId)
            }
            if let activeCollectionId {
                environments[index].lastActiveCollectionId = activeCollectionId
            }
            return .unchanged
        }

        environments.append(
            MonitorEnvironment(
                id: environmentId,
                monitors: monitors,
                lastActiveCollectionId: switched ? nil : activeCollectionId,
                lastActiveAt: now
            ))
        return switched ? .switched(restoring: nil) : .unchanged
    }

    /// Records that the user activated `id` (or cleared the selection, for
    /// `nil`) while the current environment is active — the port of the
    /// GNOME `setActiveCollectionId`, with `nil` support so that deleting
    /// the active collection clears the environment's memory of it too.
    /// No-op before the first detection, like the GNOME original.
    public mutating func recordActiveCollection(_ id: CollectionId?, at now: Date) {
        guard let index = environments.firstIndex(where: { $0.id == currentId }) else {
            return
        }
        environments[index].lastActiveCollectionId = id
        environments[index].lastActiveAt = now
    }
}
