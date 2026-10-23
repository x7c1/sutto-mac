import Foundation
import SuttoDomain
import SuttoOperations
import Testing

@testable import SuttoInfra

/// Round-trip and degrade tests for the file-backed license repository, run
/// against a per-test temp directory — never the real Application Support.
///
/// The load path's defining property is the fresh-trial degrade (design
/// decision #8): a missing, corrupt, or unknown-status file must never
/// fabricate `expired` / `invalid` and lock the user out.
@Suite @MainActor struct FileLicenseRepositoryTests {
    /// Timestamps are whole seconds so the ISO-8601 serialization (which drops
    /// sub-second precision) round-trips the `Date` exactly.
    private let validUntil = Date(timeIntervalSince1970: 1_800_000_000)
    private let lastValidated = Date(timeIntervalSince1970: 1_700_000_000)
    private let lastOnlineAt = Date(timeIntervalSince1970: 1_750_000_000)
    /// The repository's injected clock: what a missing last-online time loads
    /// as. Distinct from ``lastOnlineAt`` so the tests can tell them apart.
    private let loadTime = Date(timeIntervalSince1970: 1_760_000_000)

    private func withRepository(
        _ body: (FileLicenseRepository, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuttoInfraTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let loadTime = loadTime
        try body(FileLicenseRepository(directory: directory, now: { loadTime }), directory)
    }

    private func activatedState(status: LicenseStatus = .valid) -> LicenseState {
        LicenseState(
            status: status,
            record: LicenseRecord(
                licenseKey: "KEY-123",
                activationId: "ACT-456",
                validUntil: validUntil,
                lastValidated: lastValidated,
                status: status
            ),
            trial: TrialState(daysUsed: 3, lastUsedDate: "2026-07-16"),
            lastOnlineAt: lastOnlineAt
        )
    }

    @Test func roundTripsAnActivatedState() throws {
        try withRepository { repository, _ in
            let state = activatedState()

            try repository.save(state)

            #expect(repository.load() == state)
        }
    }

    @Test func roundTripsATrialOnlyState() throws {
        try withRepository { repository, _ in
            let state = LicenseState(
                status: .trial, record: nil,
                trial: TrialState(daysUsed: 5, lastUsedDate: "2026-07-10"), lastOnlineAt: lastOnlineAt)

            try repository.save(state)

            let loaded = repository.load()
            #expect(loaded == state)
            #expect(loaded.record == nil)
        }
    }

    /// First run: no file yet. A fresh trial, not an error.
    @Test func loadsFreshTrialWhenNoFileExists() throws {
        try withRepository { repository, _ in
            #expect(repository.load() == .freshTrial(now: loadTime))
        }
    }

    /// A corrupt file degrades to a fresh trial (design decision #8) — never to
    /// `expired` / `invalid`. A read failure is not an authoritative NO.
    @Test func loadsFreshTrialFromACorruptFileNeverFabricatingExpired() throws {
        try withRepository { repository, directory in
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(
                to: directory.appendingPathComponent("license.sutto.json"))

            let loaded = repository.load()
            #expect(loaded == .freshTrial(now: loadTime))
            #expect(loaded.status == .trial)
        }
    }

    /// An unknown status string degrades to `trial`, not a worse verdict,
    /// mirroring the GNOME `getStatus()` catch.
    @Test func loadsTrialWhenStatusStringIsUnknown() throws {
        try withRepository { repository, directory in
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let json = """
                {
                  "activationId" : "",
                  "licenseKey" : "",
                  "status" : "gibberish",
                  "trialDaysUsed" : 2,
                  "trialLastUsedDate" : "2026-07-16"
                }
                """
            try Data(json.utf8).write(
                to: directory.appendingPathComponent("license.sutto.json"))

            let loaded = repository.load()
            #expect(loaded.status == .trial)
            #expect(loaded.trial.daysUsed == 2)
        }
    }

    /// A spent trial round-trips as `trialExpired`, written with the GNOME
    /// raw value `trial-expired`.
    @Test func roundTripsATrialExpiredState() throws {
        try withRepository { repository, directory in
            let state = LicenseState(
                status: .trialExpired, record: nil,
                trial: TrialState(daysUsed: 30, lastUsedDate: "2026-07-16"), lastOnlineAt: lastOnlineAt)

            try repository.save(state)

            #expect(repository.load() == state)
            let data = try Data(
                contentsOf: directory.appendingPathComponent("license.sutto.json"))
            let root = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(root["status"] as? String == "trial-expired")
        }
    }

    /// An older version wrote a spent trial as `expired` with no license. With
    /// no record, no backend ever expired a license here, so it loads as
    /// `trialExpired`.
    @Test func loadsLegacyExpiredWithoutARecordAsTrialExpired() throws {
        try withRepository { repository, directory in
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let json = """
                {
                  "activationId" : "",
                  "licenseKey" : "",
                  "status" : "expired",
                  "trialDaysUsed" : 30,
                  "trialLastUsedDate" : "2026-07-16"
                }
                """
            try Data(json.utf8).write(
                to: directory.appendingPathComponent("license.sutto.json"))

            let loaded = repository.load()
            #expect(loaded.status == .trialExpired)
            #expect(loaded.record == nil)
            #expect(loaded.trial.daysUsed == 30)
        }
    }

    /// A stored `expired` with a license record is an authoritatively expired
    /// license and stays `expired`.
    @Test func loadsExpiredWithARecordAsExpired() throws {
        try withRepository { repository, _ in
            let state = activatedState(status: .expired)

            try repository.save(state)

            let loaded = repository.load()
            #expect(loaded.status == .expired)
            #expect(loaded.record?.status == .expired)
        }
    }

    /// The written document exposes the licensing keys (aligned with the GNOME
    /// GSettings keys) and omits the record timestamps in the trial-only state.
    @Test func writesTheExpectedFileShape() throws {
        try withRepository { repository, directory in
            try repository.save(activatedState())

            let data = try Data(
                contentsOf: directory.appendingPathComponent("license.sutto.json"))
            let root = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(
                Set(root.keys) == [
                    "status", "licenseKey", "activationId", "validUntil", "lastValidated",
                    "trialDaysUsed", "trialLastUsedDate", "lastOnlineAt", "trialProbeResult",
                ])
            #expect(root["status"] as? String == "valid")
            #expect(root["licenseKey"] as? String == "KEY-123")
            #expect(root["trialDaysUsed"] as? Int == 3)
            // ISO-8601 string, not a number.
            #expect(root["validUntil"] is String)
        }
    }

    @Test func trialOnlyFileOmitsTheRecordTimestamps() throws {
        try withRepository { repository, directory in
            try repository.save(
                LicenseState(
                    status: .trial, record: nil,
                    trial: TrialState(daysUsed: 1, lastUsedDate: "2026-07-16"), lastOnlineAt: lastOnlineAt))

            let data = try Data(
                contentsOf: directory.appendingPathComponent("license.sutto.json"))
            let root = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(root["validUntil"] == nil)
            #expect(root["lastValidated"] == nil)
            #expect(root["licenseKey"] as? String == "")
        }
    }

    // MARK: - Last-online time

    @Test func roundTripsTheLastOnlineTime() throws {
        try withRepository { repository, directory in
            try repository.save(activatedState())

            #expect(repository.load().lastOnlineAt == lastOnlineAt)
            let data = try Data(
                contentsOf: directory.appendingPathComponent("license.sutto.json"))
            let root = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            // ISO-8601 string, like the other timestamps.
            #expect(root["lastOnlineAt"] is String)
        }
    }

    /// A file written before `lastOnlineAt` existed loads with the load time,
    /// so the offline limit starts now rather than closing the gate.
    @Test func loadsAFileWithoutTheLastOnlineTimeWithTheLoadTime() throws {
        try withRepository { repository, directory in
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let json = """
                {
                  "activationId" : "ACT-456",
                  "lastValidated" : "2023-11-14T22:13:20Z",
                  "licenseKey" : "KEY-123",
                  "status" : "valid",
                  "trialDaysUsed" : 3,
                  "trialLastUsedDate" : "2026-07-16",
                  "validUntil" : "2027-01-15T08:00:00Z"
                }
                """
            try Data(json.utf8).write(
                to: directory.appendingPathComponent("license.sutto.json"))

            let loaded = repository.load()
            #expect(loaded.status == .valid)
            #expect(loaded.lastOnlineAt == loadTime)
            #expect(loaded.isGateOpen(isOnline: false, now: loadTime))
        }
    }

    /// A fresh trial and a corrupt file both start the last-online time at the
    /// load time.
    @Test func freshAndCorruptLoadsStartTheLastOnlineTimeAtTheLoadTime() throws {
        try withRepository { repository, directory in
            #expect(repository.load().lastOnlineAt == loadTime)

            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(
                to: directory.appendingPathComponent("license.sutto.json"))
            #expect(repository.load().lastOnlineAt == loadTime)
        }
    }

    // MARK: - Trial probe result

    /// Every probe result round-trips, written with the GNOME raw values.
    @Test(arguments: [
        (TrialProbeResult.none, "none"),
        (TrialProbeResult.answered, "answered"),
        (TrialProbeResult.noResponse, "no-response"),
    ])
    func roundTripsTheTrialProbeResult(result: TrialProbeResult, raw: String) throws {
        try withRepository { repository, directory in
            let state = LicenseState(
                status: .trialExpired, record: nil,
                trial: TrialState(daysUsed: 30, lastUsedDate: "2026-07-16"),
                lastOnlineAt: lastOnlineAt, trialProbeResult: result)

            try repository.save(state)

            #expect(repository.load() == state)
            let data = try Data(
                contentsOf: directory.appendingPathComponent("license.sutto.json"))
            let root = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(root["trialProbeResult"] as? String == raw)
        }
    }

    /// A file written before `trialProbeResult` existed, and one with a value
    /// this version does not know, both load as `none` — never as an open
    /// `noResponse`, and never as a load failure.
    @Test(arguments: [nil, "\"maybe\""] as [String?])
    func loadsAMissingOrUnknownTrialProbeResultAsNone(rawJSONValue: String?) throws {
        try withRepository { repository, directory in
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let probeLine = rawJSONValue.map { "\"trialProbeResult\" : \($0)," } ?? ""
            let json = """
                {
                  "activationId" : "",
                  "lastOnlineAt" : "2025-06-15T15:06:40Z",
                  "licenseKey" : "",
                  "status" : "trial-expired",
                  \(probeLine)
                  "trialDaysUsed" : 30,
                  "trialLastUsedDate" : "2026-07-16"
                }
                """
            try Data(json.utf8).write(
                to: directory.appendingPathComponent("license.sutto.json"))

            let loaded = repository.load()
            #expect(loaded.status == .trialExpired)
            #expect(loaded.trial.daysUsed == 30)
            #expect(loaded.trialProbeResult == .none)
            #expect(!loaded.isGateOpen(isOnline: true, now: loadTime))
        }
    }
}
