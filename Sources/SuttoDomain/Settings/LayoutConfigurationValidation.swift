import Foundation

/// Error describing why a decoded ``LayoutConfiguration`` was rejected.
///
/// Mirrors the rejection cases of `isValidLayoutConfiguration` in
/// `operations/layout/space-collection-operations/import-collection.ts` of
/// the GNOME version of Sutto.
public struct LayoutConfigurationValidationError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

extension LayoutConfiguration {
    /// Validates the semantic rules a configuration must satisfy before it
    /// can be imported.
    ///
    /// This is the Swift counterpart of `isValidLayoutConfiguration` in the
    /// GNOME `import-collection.ts`. The GNOME validator performs two kinds
    /// of checks: structural ones (`name` is a string, `layoutGroups` and
    /// `rows` are arrays), which `Codable` decoding already enforces here,
    /// and one semantic rule — the name must not be empty or
    /// whitespace-only (`config.name.trim() === ''` is rejected). That
    /// remaining semantic rule is what this method checks; it was
    /// deliberately deferred out of the schema PR because it sits above the
    /// codec.
    public func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LayoutConfigurationValidationError(
                message: "The configuration name must not be empty.")
        }
    }
}
