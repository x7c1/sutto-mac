import Testing

@testable import SuttoDomain

/// Behavior of the layout-minting convenience initializer, the Swift
/// counterpart of `settingToLayout` in the GNOME version's
/// `import-collection.ts` (fresh id + coordinate hash).
@Suite struct LayoutTests {
    private static func makeLayout() -> Layout {
        Layout(
            label: "Left Half",
            position: LayoutPosition(x: "0", y: "0"),
            size: LayoutSize(width: "50%", height: "100%")
        )
    }

    @Test func computesTheCoordinateHashFromPositionAndSize() {
        let layout = Self.makeLayout()
        #expect(
            layout.hash
                == generateLayoutHash(x: "0", y: "0", width: "50%", height: "100%"))
    }

    @Test func generatesAFreshIdPerLayout() {
        #expect(Self.makeLayout().id != Self.makeLayout().id)
    }
}
