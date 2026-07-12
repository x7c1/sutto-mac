import Testing

@testable import SuttoDomain

private func makeLayout(x: String, y: String, width: String, height: String) -> Layout {
    Layout(
        label: "test",
        position: LayoutPosition(x: x, y: y),
        size: LayoutSize(width: width, height: height)
    )
}

/// The GNOME version has no unit tests for frame resolution (its
/// `layout-applicator.ts` is exercised only inside GNOME Shell), so these
/// tests pin down the semantics this port copies from it: horizontal
/// expressions bind to the container width, vertical expressions to the
/// container height, and each component rounds like JavaScript's
/// `Math.round`.
@Suite struct LayoutFrameResolverTests {
    @Suite struct DimensionBinding {
        @Test func bindsXAndWidthToContainerWidth() throws {
            // On an asymmetric container, 50% resolves differently per axis.
            let layout = makeLayout(x: "50%", y: "0", width: "50%", height: "100%")
            let frame = try LayoutFrameResolver.resolve(
                layout, containerWidth: 1920, containerHeight: 1080)
            #expect(frame == LayoutFrame(x: 960, y: 0, width: 960, height: 1080))
        }

        @Test func bindsYAndHeightToContainerHeight() throws {
            let layout = makeLayout(x: "0", y: "50%", width: "100%", height: "50%")
            let frame = try LayoutFrameResolver.resolve(
                layout, containerWidth: 1920, containerHeight: 1080)
            #expect(frame == LayoutFrame(x: 0, y: 540, width: 1920, height: 540))
        }

        @Test func bindsFractionsPerAxis() throws {
            let layout = makeLayout(x: "1/3", y: "1/3", width: "1/3", height: "1/3")
            let frame = try LayoutFrameResolver.resolve(
                layout, containerWidth: 1920, containerHeight: 1080)
            #expect(frame == LayoutFrame(x: 640, y: 360, width: 640, height: 360))
        }
    }

    @Suite struct CompositeExpressions {
        @Test func resolvesPixelArithmeticPerComponent() throws {
            // A centered 300x200 px window on a 1920x1080 container.
            let layout = makeLayout(
                x: "50% - 150px", y: "50% - 100px", width: "300px", height: "200px")
            let frame = try LayoutFrameResolver.resolve(
                layout, containerWidth: 1920, containerHeight: 1080)
            #expect(frame == LayoutFrame(x: 810, y: 440, width: 300, height: 200))
        }

        @Test func resolvesPaddedLayout() throws {
            let layout = makeLayout(
                x: "10px", y: "10px", width: "100% - 20px", height: "100% - 20px")
            let frame = try LayoutFrameResolver.resolve(
                layout, containerWidth: 1920, containerHeight: 1080)
            #expect(frame == LayoutFrame(x: 10, y: 10, width: 1900, height: 1060))
        }
    }

    @Suite struct Rounding {
        @Test func roundsEachComponentLikeMathRound() throws {
            // 1/3 of 1366 = 455.333... -> 455; 2/3 of 1366 = 910.666... -> 911.
            let layout = makeLayout(x: "2/3", y: "0", width: "1/3", height: "100%")
            let frame = try LayoutFrameResolver.resolve(
                layout, containerWidth: 1366, containerHeight: 768)
            #expect(frame == LayoutFrame(x: 911, y: 0, width: 455, height: 768))
        }

        @Test func roundsHalfTowardPositiveInfinity() throws {
            // 50% of 301 = 150.5 -> 151, matching JavaScript's Math.round.
            let layout = makeLayout(x: "0", y: "0", width: "50%", height: "50%")
            let frame = try LayoutFrameResolver.resolve(
                layout, containerWidth: 301, containerHeight: 301)
            #expect(frame == LayoutFrame(x: 0, y: 0, width: 151, height: 151))
        }
    }

    @Suite struct InvalidExpressions {
        @Test func throwsParseErrorForInvalidExpression() {
            let layout = makeLayout(x: "abc", y: "0", width: "50%", height: "100%")
            #expect(throws: LayoutExpressionParseError.invalidTerm("abc")) {
                try LayoutFrameResolver.resolve(
                    layout, containerWidth: 1920, containerHeight: 1080)
            }
        }

        @Test func throwsParseErrorForEmptyExpression() {
            let layout = makeLayout(x: "0", y: "0", width: "", height: "100%")
            #expect(throws: LayoutExpressionParseError.emptyExpression) {
                try LayoutFrameResolver.resolve(
                    layout, containerWidth: 1920, containerHeight: 1080)
            }
        }
    }
}
