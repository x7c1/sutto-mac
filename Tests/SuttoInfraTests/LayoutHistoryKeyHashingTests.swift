import Testing

@testable import SuttoInfra

/// Tests for the concrete SHA-256 key hasher injected into the domain
/// history rule.
@Suite struct LayoutHistoryKeyHashingTests {
    @Test func isDeterministic() {
        #expect(
            LayoutHistoryKeyHashing.hash("com.apple.Safari")
                == LayoutHistoryKeyHashing.hash("com.apple.Safari"))
    }

    @Test func producesSixteenHexCharacters() {
        let digest = LayoutHistoryKeyHashing.hash("com.apple.Safari")
        #expect(digest.count == 16)
        #expect(digest.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    /// Pins the output for known inputs to the first 16 hex characters of
    /// their SHA-256 digest (the GNOME `hashString`), so an accidental change
    /// to the algorithm — which would silently invalidate every stored
    /// history key — is caught.
    @Test(
        arguments: [
            ("", "e3b0c44298fc1c14"),
            ("hello", "2cf24dba5fb0a30e"),
        ])
    func matchesKnownDigests(input: String, expected: String) {
        #expect(LayoutHistoryKeyHashing.hash(input) == expected)
    }

    @Test func distinctInputsHashDifferently() {
        #expect(
            LayoutHistoryKeyHashing.hash("com.apple.Safari")
                != LayoutHistoryKeyHashing.hash("com.google.Chrome"))
    }

    /// The injectable value and the static function are the same transform.
    @Test func sha256HasherMatchesTheFunction() {
        #expect(LayoutHistoryKeyHashing.sha256("hello") == LayoutHistoryKeyHashing.hash("hello"))
    }
}
