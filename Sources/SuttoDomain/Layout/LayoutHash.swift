/// Generates a deterministic hash from layout coordinates and dimensions.
/// Used for detecting layouts with identical coordinates (duplicate
/// detection).
///
/// This is a faithful port of `generateLayoutHash` in
/// `domain/layout/layout-hash.ts` of the GNOME version, and MUST produce
/// bit-identical output for identical input: the hash is stored in exported
/// collection JSON, so both apps have to agree on it. The algorithm is the
/// classic Java-style `hashCode` over the UTF-16 code units of
/// `"x|y|width|height"` — JavaScript's `charCodeAt` yields UTF-16 code
/// units, so the Swift port iterates `String.utf16`, and the JS bitwise
/// truncation to a signed 32-bit integer maps to `Int32` wrapping
/// arithmetic (both reduce modulo 2^32 at every step).
///
/// - Parameters:
///   - x: X coordinate expression
///   - y: Y coordinate expression
///   - width: Width expression
///   - height: Height expression
/// - Returns: Hash string in format `"hash-{hex}"`, where `{hex}` is the
///   unsigned 32-bit value in lowercase hex, zero-padded to 8 characters.
public func generateLayoutHash(x: String, y: String, width: String, height: String) -> String {
    let input = "\(x)|\(y)|\(width)|\(height)"

    var hash: Int32 = 0
    for unit in input.utf16 {
        hash = (hash &<< 5) &- hash &+ Int32(unit)
    }

    let hexHash = String(UInt32(bitPattern: hash), radix: 16)
    let padded = String(repeating: "0", count: max(0, 8 - hexHash.count)) + hexHash

    return "hash-\(padded)"
}
