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

    private func withRepository(
        _ body: (FileLicenseRepository, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuttoInfraTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(FileLicenseRepository(directory: directory), directory)
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
            trial: TrialState(daysUsed: 3, lastUsedDate: "2026-07-16")
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
                trial: TrialState(daysUsed: 5, lastUsedDate: "2026-07-10"))

            try repository.save(state)

            let loaded = repository.load()
            #expect(loaded == state)
            #expect(loaded.record == nil)
        }
    }

    /// First run: no file yet. A fresh trial, not an error.
    @Test func loadsFreshTrialWhenNoFileExists() throws {
        try withRepository { repository, _ in
            #expect(repository.load() == .freshTrial)
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
            #expect(loaded == .freshTrial)
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
                    "trialDaysUsed", "trialLastUsedDate",
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
                    trial: TrialState(daysUsed: 1, lastUsedDate: "2026-07-16")))

            let data = try Data(
                contentsOf: directory.appendingPathComponent("license.sutto.json"))
            let root = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(root["validUntil"] == nil)
            #expect(root["lastValidated"] == nil)
            #expect(root["licenseKey"] as? String == "")
        }
    }
}
