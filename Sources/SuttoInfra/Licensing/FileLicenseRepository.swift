import Foundation
import SuttoDomain
import SuttoOperations
import os

/// File-based ``SuttoOperations/LicenseRepository`` persisting the licensing
/// aggregate to a JSON file, by default next to the collection files under
/// `~/Library/Application Support/Sutto/`.
///
/// Where the GNOME version spreads licensing across GSettings keys
/// (`infra/glib/license-repository.ts`), the macOS port keeps the whole
/// aggregate in one document (design decision #7), written atomically so a
/// crash mid-write can never leave the status and the trial disagreeing. The
/// file follows the same conventions as ``FileMonitorEnvironmentRepository``
/// and ``FileSpaceCollectionRepository``: a `Raw…` `Codable` shape, an
/// `.atomic` full-write, and `[.prettyPrinted, .sortedKeys]` output.
///
/// Unlike those two — which degrade a bad file to "nothing stored" — a missing
/// or corrupt license file degrades to a **fresh trial**
/// (``SuttoOperations/LicenseState/freshTrial``), never to `expired` /
/// `invalid` (design decision #8). A read failure is not an authoritative NO,
/// so it must not close the gate; a rare corruption recovers by re-activating.
public final class FileLicenseRepository: LicenseRepository {
    /// File name in the licensing family of `*.sutto.json` documents.
    static let fileName = "license.sutto.json"

    private let fileURL: URL
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "persistence")

    /// - Parameter directory: the directory holding the file. Injected so
    ///   tests run against a temp directory instead of the real Application
    ///   Support; the app passes
    ///   `FileSpaceCollectionRepository.defaultDirectory()`.
    public init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName)
    }

    public func load() -> LicenseState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // First run: no file yet. A fresh trial, not an error.
            return .freshTrial
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try Self.decoder.decode(RawLicenseState.self, from: data).licenseState
        } catch {
            // Corrupt or unreadable: degrade to a fresh trial, never to a
            // worse verdict (design decision #8).
            logger.error(
                """
                failed to load license state from \
                \(self.fileURL.path, privacy: .public); degrading to a fresh trial: \
                \(String(describing: error), privacy: .public)
                """)
            return .freshTrial
        }
    }

    public func save(_ state: LicenseState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        // Pretty and key-sorted like the sibling repositories — the file is
        // user-visible and rewrites stay diffable.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(RawLicenseState(state))

        // .atomic writes to a temp file and renames it into place, so a crash
        // mid-write can never leave the aggregate half-updated.
        try data.write(to: fileURL, options: .atomic)

        logger.info(
            "saved license state (status \(state.status.rawValue, privacy: .public)) to \(self.fileURL.path, privacy: .public)"
        )
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Raw JSON format

/// The on-disk shape. The keys line up one-for-one with the GNOME GSettings
/// keys (`gschema.xml`): `status` ↔ `license-status`, `licenseKey` ↔
/// `license-key`, `activationId` ↔ `license-activation-id`, `validUntil` ↔
/// `license-valid-until`, `lastValidated` ↔ `license-last-validated`,
/// `trialDaysUsed` ↔ `trial-days-used`, `trialLastUsedDate` ↔
/// `trial-last-used-date`.
///
/// The two timestamps are ISO-8601 strings rather than GNOME's int64 seconds:
/// the file is macOS-only with no byte-compatibility requirement, so
/// readability wins (design "未確定" note). They are absent entirely in the
/// trial-only state (no ``LicenseRecord``), which is how ``licenseState``
/// tells "activated" from "trial", mirroring the GNOME `loadLicense()` empty
/// key / activation check.
private struct RawLicenseState: Codable {
    /// The raw status string; its values match ``SuttoDomain/LicenseStatus``'s
    /// raw values (and the GNOME statuses), so an unknown value degrades to
    /// `trial` on load rather than being rejected.
    var status: String
    /// Empty when no license is activated (the GNOME serializer writes `''`).
    var licenseKey: String
    var activationId: String
    /// Present only when a license is activated.
    var validUntil: Date?
    var lastValidated: Date?
    var trialDaysUsed: Int
    var trialLastUsedDate: String

    init(_ state: LicenseState) {
        status = state.status.rawValue
        licenseKey = state.record?.licenseKey ?? ""
        activationId = state.record?.activationId ?? ""
        validUntil = state.record?.validUntil
        lastValidated = state.record?.lastValidated
        trialDaysUsed = state.trial.daysUsed
        trialLastUsedDate = state.trial.lastUsedDate
    }

    /// The aggregate this document represents. An unknown status string
    /// degrades to `trial` (never a worse verdict, design decision #8), and a
    /// record is reconstructed only when both the key and activation id are
    /// present — matching the GNOME `loadLicense()` null check.
    var licenseState: LicenseState {
        let resolvedStatus = LicenseStatus(rawValue: status) ?? .trial
        let trial = TrialState(daysUsed: trialDaysUsed, lastUsedDate: trialLastUsedDate)

        guard !licenseKey.isEmpty, !activationId.isEmpty else {
            return LicenseState(status: resolvedStatus, record: nil, trial: trial)
        }

        let record = LicenseRecord(
            licenseKey: licenseKey,
            activationId: activationId,
            validUntil: validUntil ?? Date(timeIntervalSince1970: 0),
            lastValidated: lastValidated ?? Date(timeIntervalSince1970: 0),
            status: resolvedStatus
        )
        return LicenseState(status: resolvedStatus, record: record, trial: trial)
    }
}
