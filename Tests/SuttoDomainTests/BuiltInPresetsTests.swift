import Testing

@testable import SuttoDomain

/// Resolves every layout in a group and pairs each frame with its label.
private func resolveFrames(
    of group: LayoutGroup,
    containerWidth: Double,
    containerHeight: Double
) throws -> [(label: String, frame: LayoutFrame)] {
    try group.layouts.map { layout in
        let frame = try LayoutFrameResolver.resolve(
            layout, containerWidth: containerWidth, containerHeight: containerHeight)
        return (layout.label, frame)
    }
}

private func group(named name: String) throws -> LayoutGroup {
    let group = BuiltInPresets.standardLayoutGroups.first { $0.name == name }
    return try #require(group)
}

/// The GNOME version has no unit tests for `preset-config.ts` /
/// `preset-generator.ts`, so these tests are the compatibility pin for this
/// port: the group vocabulary must match what the GNOME preset generator
/// produces for a single standard landscape monitor, and each layout must
/// resolve to the exact pixel rect the GNOME applicator would compute.
@Suite struct BuiltInPresetsTests {
    @Suite struct Vocabulary {
        @Test func matchesStandardLayoutGroupNamesInOrder() {
            // STANDARD_LAYOUT_GROUP_NAMES in the GNOME preset-config.ts.
            #expect(
                BuiltInPresets.standardLayoutGroups.map(\.name) == [
                    "vertical 2-split",
                    "horizontal 2-split",
                    "vertical 3-split",
                    "full screen",
                ])
        }

        @Test func matchesLayoutLabelsInOrder() throws {
            #expect(try group(named: "vertical 2-split").layouts.map(\.label) == [
                "Left Half", "Right Half",
            ])
            #expect(try group(named: "horizontal 2-split").layouts.map(\.label) == [
                "Top Half", "Bottom Half",
            ])
            #expect(try group(named: "vertical 3-split").layouts.map(\.label) == [
                "Left Third", "Center Third", "Right Third",
            ])
            #expect(try group(named: "full screen").layouts.map(\.label) == ["full"])
        }

        @Test func everyExpressionParses() throws {
            for group in BuiltInPresets.standardLayoutGroups {
                for layout in group.layouts {
                    _ = try LayoutExpressionParser.parse(layout.position.x)
                    _ = try LayoutExpressionParser.parse(layout.position.y)
                    _ = try LayoutExpressionParser.parse(layout.size.width)
                    _ = try LayoutExpressionParser.parse(layout.size.height)
                }
            }
        }
    }

    /// Exact pixel rects on a representative 1920x1080 work area.
    @Suite struct FramesOn1920x1080 {
        private static let width: Double = 1920
        private static let height: Double = 1080

        @Test func vertical2Split() throws {
            let frames = try resolveFrames(
                of: group(named: "vertical 2-split"),
                containerWidth: Self.width, containerHeight: Self.height)
            #expect(frames[0].label == "Left Half")
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 960, height: 1080))
            #expect(frames[1].label == "Right Half")
            #expect(frames[1].frame == LayoutFrame(x: 960, y: 0, width: 960, height: 1080))
        }

        @Test func horizontal2Split() throws {
            let frames = try resolveFrames(
                of: group(named: "horizontal 2-split"),
                containerWidth: Self.width, containerHeight: Self.height)
            #expect(frames[0].label == "Top Half")
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 1920, height: 540))
            #expect(frames[1].label == "Bottom Half")
            #expect(frames[1].frame == LayoutFrame(x: 0, y: 540, width: 1920, height: 540))
        }

        @Test func vertical3Split() throws {
            let frames = try resolveFrames(
                of: group(named: "vertical 3-split"),
                containerWidth: Self.width, containerHeight: Self.height)
            #expect(frames[0].label == "Left Third")
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 640, height: 1080))
            #expect(frames[1].label == "Center Third")
            #expect(frames[1].frame == LayoutFrame(x: 640, y: 0, width: 640, height: 1080))
            #expect(frames[2].label == "Right Third")
            #expect(frames[2].frame == LayoutFrame(x: 1280, y: 0, width: 640, height: 1080))
        }

        @Test func fullScreen() throws {
            let frames = try resolveFrames(
                of: group(named: "full screen"),
                containerWidth: Self.width, containerHeight: Self.height)
            #expect(frames[0].label == "full")
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 1920, height: 1080))
        }
    }

    /// A container whose width is not divisible by three, checking that the
    /// thirds round exactly like the GNOME version (Math.round per component).
    @Suite struct FramesOnIndivisibleContainer {
        @Test func vertical3SplitOn1366x768() throws {
            let frames = try resolveFrames(
                of: group(named: "vertical 3-split"),
                containerWidth: 1366, containerHeight: 768)
            // 1/3 of 1366 = 455.333... -> 455; 2/3 of 1366 = 910.666... -> 911.
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 455, height: 768))
            #expect(frames[1].frame == LayoutFrame(x: 455, y: 0, width: 455, height: 768))
            #expect(frames[2].frame == LayoutFrame(x: 911, y: 0, width: 455, height: 768))
        }
    }
}
