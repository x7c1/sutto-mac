import CryptoKit
import Foundation
import SuttoDomain

/// The concrete ``SuttoDomain/LayoutHistoryKeyHasher`` the domain history
/// rule is injected with.
///
/// Ports the GNOME `hashString`
/// (`infra/file/file-layout-history-repository.ts`): SHA-256 of the string's
/// UTF-8 bytes, rendered as lowercase hex and truncated to the first 16
/// characters. The raw bundle identifier / window title is never normalized
/// (no lowercasing, trimming, or truncation), so the hash keys on the exact
/// string — matching the GNOME privacy design, which keeps raw app names and
/// window titles out of the history file.
///
/// This lives in the infra layer because it needs `CryptoKit`, which
/// `SuttoDomain` may not import (see `docs/guides/architecture.md`). The
/// transform is pure and deterministic: the same input always yields the same
/// 16-character digest, so a history file written on one run keys identically
/// on the next.
public enum LayoutHistoryKeyHashing {
    /// Number of leading hex characters kept, matching the GNOME
    /// `.substring(0, 16)`.
    private static let hexLength = 16

    /// A ready-to-inject ``SuttoDomain/LayoutHistoryKeyHasher``. Computed
    /// rather than stored so it never becomes shared mutable global state —
    /// each access hands back the same pure `hash(_:)` transform.
    public static var sha256: LayoutHistoryKeyHasher { hash(_:) }

    /// SHA-256 of `value`'s UTF-8 bytes as lowercase hex, truncated to the
    /// first 16 characters.
    public static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(hexLength))
    }
}
