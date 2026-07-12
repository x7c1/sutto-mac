import Testing

@testable import SuttoDomain

/// Compatibility pins for `generateLayoutHash`.
///
/// The GNOME version has no unit tests for `layout-hash.ts`, so these
/// expected values were obtained by executing the actual TypeScript function
/// (`src/domain/layout/layout-hash.ts` at the sutto repository) with
/// Node.js v24 native type stripping — they are NOT hand-derived. The hash
/// is persisted inside exported collection JSON, so both apps must produce
/// bit-identical values for identical input.
@Suite struct LayoutHashTests {
    /// (x, y, width, height) → expected hash, computed by the GNOME
    /// implementation. The first eight rows are the coordinates of every
    /// built-in preset layout.
    private static let pins: [(x: String, y: String, width: String, height: String, expected: String)] = [
        ("0", "0", "50%", "100%", "hash-e1d7a9be"),
        ("50%", "0", "50%", "100%", "hash-08b184c4"),
        ("0", "0", "100%", "50%", "hash-507072da"),
        ("0", "50%", "100%", "50%", "hash-a4e8b460"),
        ("0", "0", "1/3", "100%", "hash-255093b3"),
        ("1/3", "0", "1/3", "100%", "hash-41e74cee"),
        ("2/3", "0", "1/3", "100%", "hash-23c5168d"),
        ("0", "0", "100%", "100%", "hash-bd9c1864"),
        // Empty components: hashes only the "|||" separators, and pins the
        // zero-padding of hex values shorter than 8 digits.
        ("", "", "", "", "hash-0001e0fc"),
        // Expressions with spaces and px units.
        ("50% - 10px", "10px", "100% - 20px", "1/2", "hash-6cabd9f4"),
        // Non-ASCII input, including a surrogate pair (𩸽): pins that the
        // Swift port hashes UTF-16 code units exactly like JavaScript's
        // charCodeAt, not Unicode scalars or UTF-8 bytes.
        ("あ", "𩸽", "0", "0", "hash-227bfe18"),
    ]

    @Test(arguments: pins.indices) func matchesTheGnomeImplementation(index: Int) {
        let pin = Self.pins[index]
        let hash = generateLayoutHash(x: pin.x, y: pin.y, width: pin.width, height: pin.height)
        #expect(hash == pin.expected, "input: \(pin)")
    }

    @Test func isDeterministic() {
        let first = generateLayoutHash(x: "0", y: "0", width: "50%", height: "100%")
        let second = generateLayoutHash(x: "0", y: "0", width: "50%", height: "100%")
        #expect(first == second)
    }

    @Test func distinguishesComponentBoundaries() {
        // "ab|c" vs "a|bc": the separator keeps components apart.
        let first = generateLayoutHash(x: "ab", y: "c", width: "", height: "")
        let second = generateLayoutHash(x: "a", y: "bc", width: "", height: "")
        #expect(first != second)
    }
}
