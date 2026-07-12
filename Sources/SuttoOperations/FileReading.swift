import Foundation

/// Reads file contents on behalf of use cases, so the operations layer
/// never performs file I/O itself (that belongs to the infra layer — see
/// docs/guides/architecture.md). Tests substitute an in-memory stub.
@MainActor
public protocol FileReading {
    /// Returns the contents of the file at `url`, throwing when it cannot
    /// be read (missing file, no permission, ...).
    func read(from url: URL) throws -> Data
}
