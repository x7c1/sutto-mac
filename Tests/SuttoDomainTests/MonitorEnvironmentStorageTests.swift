import Foundation
import Testing

@testable import SuttoDomain

/// The environment transition rules of ``MonitorEnvironmentStorage``: the
/// pure port of the GNOME `detectAndSaveMonitors` bookkeeping.
@Suite struct MonitorEnvironmentStorageTests {
    private let laptop = MonitorFixtures.laptopOnly
    private let desk = MonitorFixtures.laptopWithUltrawide
    private let collection = CollectionId.generate()
    private let otherCollection = CollectionId.generate()
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_200)

    // MARK: - First detection (migration)

    /// The very first detection migrates the pre-existing single
    /// active-collection preference into the environment's record: the
    /// setup the user has been using inherits their selection.
    @Test func theFirstDetectionSeedsTheEnvironmentWithTheActiveSelection() {
        var storage = MonitorEnvironmentStorage()

        let change = storage.update(monitors: desk, activeCollectionId: collection, at: t0)

        #expect(change == .unchanged)
        #expect(storage.currentEnvironment?.lastActiveCollectionId == collection)
        #expect(storage.currentEnvironment?.monitors == desk)
        #expect(storage.environments.count == 1)
    }

    @Test func theFirstDetectionWithoutASelectionRecordsNone() {
        var storage = MonitorEnvironmentStorage()

        let change = storage.update(monitors: desk, activeCollectionId: nil, at: t0)

        #expect(change == .unchanged)
        #expect(storage.currentEnvironment?.lastActiveCollectionId == nil)
    }

    // MARK: - Re-detecting the same environment

    /// Re-detecting the unchanged environment back-fills the live
    /// selection into its record — the GNOME `currentActiveCollectionId`
    /// write-back — and refreshes geometry and timestamp.
    @Test func reDetectingTheSameEnvironmentBackFillsTheSelection() {
        var storage = MonitorEnvironmentStorage()
        _ = storage.update(monitors: desk, activeCollectionId: nil, at: t0)

        let change = storage.update(monitors: desk, activeCollectionId: collection, at: t1)

        #expect(change == .unchanged)
        #expect(storage.currentEnvironment?.lastActiveCollectionId == collection)
        #expect(storage.currentEnvironment?.lastActiveAt == t1)
    }

    /// A nil live selection does not erase a recorded one: only an actual
    /// selection is written back, like the GNOME `if` around the
    /// write-back.
    @Test func reDetectingWithoutASelectionKeepsTheRecordedOne() {
        var storage = MonitorEnvironmentStorage()
        _ = storage.update(monitors: desk, activeCollectionId: collection, at: t0)

        _ = storage.update(monitors: desk, activeCollectionId: nil, at: t1)

        #expect(storage.currentEnvironment?.lastActiveCollectionId == collection)
    }

    // MARK: - Switching environments

    /// Entering a known environment reports its remembered collection for
    /// the caller to activate.
    @Test func switchingToAKnownEnvironmentRestoresItsCollection() {
        var storage = MonitorEnvironmentStorage()
        _ = storage.update(monitors: laptop, activeCollectionId: collection, at: t0)
        _ = storage.update(monitors: desk, activeCollectionId: otherCollection, at: t1)

        let change = storage.update(monitors: laptop, activeCollectionId: otherCollection, at: t2)

        #expect(change == .switched(restoring: collection))
        #expect(storage.currentId == MonitorEnvironmentId.generate(for: laptop))
    }

    /// Entering an unseen environment starts with no selection — it does
    /// NOT inherit the previous environment's collection, so the caller
    /// falls back to the default preset. (Deliberate deviation from the
    /// GNOME handler, which leaves the old collection active; see the
    /// `Change` documentation.)
    @Test func switchingToANewEnvironmentStartsWithoutASelection() {
        var storage = MonitorEnvironmentStorage()
        _ = storage.update(monitors: laptop, activeCollectionId: collection, at: t0)

        let change = storage.update(monitors: desk, activeCollectionId: collection, at: t1)

        #expect(change == .switched(restoring: nil))
        #expect(storage.currentEnvironment?.lastActiveCollectionId == nil)
        #expect(storage.environments.count == 2)
    }

    /// The docking round trip: each environment keeps its own selection
    /// across any number of switches.
    @Test func eachEnvironmentRemembersItsOwnSelectionAcrossSwitches() {
        var storage = MonitorEnvironmentStorage()
        _ = storage.update(monitors: desk, activeCollectionId: collection, at: t0)

        // Undock: new environment, no selection; the user then picks one.
        _ = storage.update(monitors: laptop, activeCollectionId: collection, at: t1)
        storage.recordActiveCollection(otherCollection, at: t1)

        // Redock: the desk selection comes back.
        #expect(
            storage.update(monitors: desk, activeCollectionId: otherCollection, at: t2)
                == .switched(restoring: collection))

        // Undock again: the laptop selection comes back.
        #expect(
            storage.update(monitors: laptop, activeCollectionId: collection, at: t2)
                == .switched(restoring: otherCollection))
    }

    /// Every detection overwrites the entered environment's stored
    /// monitors, like the GNOME original: identical geometry is what makes
    /// it the same environment, but the *work areas* can still have
    /// changed (Dock moved or resized) and the stored records should
    /// carry the fresh ones.
    @Test func switchingRefreshesTheEnteredEnvironmentsMonitors() {
        var storage = MonitorEnvironmentStorage()
        _ = storage.update(monitors: laptop, activeCollectionId: nil, at: t0)
        _ = storage.update(monitors: desk, activeCollectionId: nil, at: t1)

        let laptopWithDock = [
            Monitor(
                index: 0,
                geometry: laptop[0].geometry,
                workArea: PixelRect(x: 0, y: 25, width: 1512, height: 887),
                isPrimary: true
            )
        ]
        _ = storage.update(monitors: laptopWithDock, activeCollectionId: nil, at: t2)

        #expect(storage.currentEnvironment?.monitors == laptopWithDock)
        #expect(storage.currentEnvironment?.lastActiveAt == t2)
    }

    // MARK: - Recording selections

    @Test func recordingWritesToTheCurrentEnvironment() {
        var storage = MonitorEnvironmentStorage()
        _ = storage.update(monitors: laptop, activeCollectionId: nil, at: t0)
        _ = storage.update(monitors: desk, activeCollectionId: nil, at: t1)

        storage.recordActiveCollection(collection, at: t2)

        #expect(storage.currentEnvironment?.lastActiveCollectionId == collection)
        // The other environment is untouched.
        #expect(
            storage.environments
                .first { $0.id == MonitorEnvironmentId.generate(for: laptop) }?
                .lastActiveCollectionId == nil)
    }

    /// Recording `nil` clears the memory — deleting the active collection
    /// must not leave a dead id to be restored later.
    @Test func recordingNilClearsTheSelection() {
        var storage = MonitorEnvironmentStorage()
        _ = storage.update(monitors: laptop, activeCollectionId: collection, at: t0)

        storage.recordActiveCollection(nil, at: t1)

        #expect(storage.currentEnvironment?.lastActiveCollectionId == nil)
    }

    /// Before any detection there is no current environment; recording is
    /// a no-op like the GNOME `setActiveCollectionId` without a match.
    @Test func recordingBeforeAnyDetectionIsANoOp() {
        var storage = MonitorEnvironmentStorage()

        storage.recordActiveCollection(collection, at: t0)

        #expect(storage == MonitorEnvironmentStorage())
    }
}
