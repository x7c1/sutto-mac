import Foundation
import SuttoDomain
import os

/// Why an import failed, carrying a user-presentable reason.
///
/// The GNOME importer collapses every failure into `null` plus a log line;
/// the mac app surfaces failures in an alert, so the cases stay distinct
/// and each carries enough detail to say *why*.
public enum LayoutImportError: Error, Equatable {
    /// The file could not be read at all (missing, unreadable, ...).
    case unreadableFile(reason: String)

    /// The contents are not well-formed JSON.
    case invalidJSON(reason: String)

    /// The JSON is well-formed but is not a valid layout configuration
    /// (wrong shape, or a semantic rule like the empty-name rejection).
    case invalidConfiguration(reason: String)

    /// The configuration was imported but persisting it failed.
    case saveFailed(reason: String)

    /// Short, specific message for the alert presenting this failure.
    public var userMessage: String {
        switch self {
        case .unreadableFile(let reason):
            "The file could not be read. \(reason)"
        case .invalidJSON(let reason):
            "The file is not valid JSON. \(reason)"
        case .invalidConfiguration(let reason):
            "The file is not a valid layout configuration. \(reason)"
        case .saveFailed(let reason):
            "The imported layouts could not be saved. \(reason)"
        }
    }
}

/// Imports a sutto-compatible layout-configuration JSON file as a custom
/// ``SuttoDomain/SpaceCollection``.
///
/// Pipeline (mirroring `importLayoutConfigurationFromJson` in the GNOME
/// `import-collection.ts`): read the file → parse the JSON as a
/// ``SuttoDomain/LayoutConfiguration`` → validate it (including the
/// empty-name rejection) → convert it to rows, minting ids and hashes →
/// hand it to the repository, which mints the collection id and persists.
///
/// One deliberate addition over GNOME: on success the imported collection
/// is made *active*, so the panel shows it immediately. GNOME leaves
/// selection to its preferences UI; the mac settings screen (selection and
/// deletion) is the next PR, and until it lands importing is the only way
/// to select a collection.
@MainActor
public final class ImportCollectionUseCase {
    private let repository: any SpaceCollectionRepository
    private let preferences: any PreferencesRepository
    private let fileReader: any FileReading
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "import")

    public init(
        repository: any SpaceCollectionRepository,
        preferences: any PreferencesRepository,
        fileReader: any FileReading
    ) {
        self.repository = repository
        self.preferences = preferences
        self.fileReader = fileReader
    }

    /// Imports the layout-configuration JSON at `url`. On success the new
    /// collection is persisted and made active; on failure nothing is
    /// stored and the error says why.
    public func importCollection(at url: URL) -> Result<SpaceCollection, LayoutImportError> {
        let data: Data
        do {
            data = try fileReader.read(from: url)
        } catch {
            return .failure(.unreadableFile(reason: error.localizedDescription))
        }

        let configuration: LayoutConfiguration
        do {
            configuration = try JSONDecoder().decode(LayoutConfiguration.self, from: data)
        } catch let error as DecodingError {
            // GNOME separates JSON.parse errors from shape validation;
            // JSONDecoder reports both as DecodingError, with syntax errors
            // surfacing as .dataCorrupted at the root. Split them back so
            // the alert can tell "not JSON" from "JSON, wrong shape".
            return .failure(Self.importError(for: error))
        } catch {
            return .failure(.invalidJSON(reason: error.localizedDescription))
        }

        do {
            try configuration.validate()
        } catch {
            return .failure(.invalidConfiguration(reason: String(describing: error)))
        }

        let rows = ImportConversion.spacesRows(from: configuration) { message in
            logger.warning("\(message, privacy: .public)")
        }

        do {
            let collection = try repository.addCustomCollection(name: configuration.name, rows: rows)
            preferences.setActiveCollectionId(collection.id)
            logger.info(
                "imported \"\(collection.name, privacy: .public)\" as custom collection \(collection.id.description, privacy: .public)"
            )
            return .success(collection)
        } catch {
            return .failure(.saveFailed(reason: error.localizedDescription))
        }
    }

    // MARK: - Decoding-error presentation

    private static func importError(for error: DecodingError) -> LayoutImportError {
        switch error {
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            // Root-level dataCorrupted is JSONDecoder's malformed-JSON
            // signal (the underlying JSON parser failed).
            return .invalidJSON(reason: "The contents could not be parsed.")
        case .dataCorrupted(let context):
            return .invalidConfiguration(
                reason: "Invalid value at \"\(path(of: context))\".")
        case .keyNotFound(let key, let context):
            return .invalidConfiguration(
                reason: "Missing field \"\(path(of: context, appending: key))\".")
        case .valueNotFound(_, let context):
            return .invalidConfiguration(
                reason: "Missing value at \"\(path(of: context))\".")
        case .typeMismatch(_, let context):
            return .invalidConfiguration(
                reason: "Unexpected value type at \"\(path(of: context))\".")
        @unknown default:
            return .invalidConfiguration(reason: String(describing: error))
        }
    }

    /// Renders a coding path like `layoutGroups[0].layouts[2].label`.
    private static func path(
        of context: DecodingError.Context, appending key: (any CodingKey)? = nil
    ) -> String {
        var keys = context.codingPath
        if let key {
            keys.append(key)
        }
        guard !keys.isEmpty else { return "(root)" }

        return keys.reduce(into: "") { rendered, key in
            if let index = key.intValue {
                rendered += "[\(index)]"
            } else {
                rendered += rendered.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}
