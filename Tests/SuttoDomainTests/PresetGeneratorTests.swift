import Testing

@testable import SuttoDomain

/// One layout of the pinned tables below: the expressions and the exact
/// hash the GNOME generator mints for them.
private struct ExpectedLayout {
    let label: String
    let x: String
    let y: String
    let width: String
    let height: String
    let hash: String
}

private struct ExpectedGroup {
    let name: String
    let layouts: [ExpectedLayout]
}

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

/// The layout groups a generated preset assigns to the primary display, in
/// reading order (rows top to bottom, spaces left to right) — the order the
/// panel renders spaces in.
private func primaryGroups(of collection: SpaceCollection) -> [LayoutGroup] {
    collection.rows
        .flatMap(\.spaces)
        .compactMap { $0.displays[PanelDisplayKey.primary] }
}

private func group(named name: String, in collection: SpaceCollection) throws -> LayoutGroup {
    try #require(primaryGroups(of: collection).first { $0.name == name })
}

/// `generatePreset(1, 'standard', …)` executed in TypeScript: the four
/// standard groups with their layouts and hashes.
private let standardGroups: [ExpectedGroup] = [
    ExpectedGroup(
        name: "vertical 2-split",
        layouts: [
            ExpectedLayout(
                label: "Left Half", x: "0", y: "0",
                width: "50%", height: "100%", hash: "hash-e1d7a9be"),
            ExpectedLayout(
                label: "Right Half", x: "50%", y: "0",
                width: "50%", height: "100%", hash: "hash-08b184c4"),
        ]),
    ExpectedGroup(
        name: "horizontal 2-split",
        layouts: [
            ExpectedLayout(
                label: "Top Half", x: "0", y: "0",
                width: "100%", height: "50%", hash: "hash-507072da"),
            ExpectedLayout(
                label: "Bottom Half", x: "0", y: "50%",
                width: "100%", height: "50%", hash: "hash-a4e8b460"),
        ]),
    ExpectedGroup(
        name: "vertical 3-split",
        layouts: [
            ExpectedLayout(
                label: "Left Third", x: "0", y: "0",
                width: "1/3", height: "100%", hash: "hash-255093b3"),
            ExpectedLayout(
                label: "Center Third", x: "1/3", y: "0",
                width: "1/3", height: "100%", hash: "hash-41e74cee"),
            ExpectedLayout(
                label: "Right Third", x: "2/3", y: "0",
                width: "1/3", height: "100%", hash: "hash-23c5168d"),
        ]),
    ExpectedGroup(
        name: "full screen",
        layouts: [
            ExpectedLayout(
                label: "full", x: "0", y: "0",
                width: "100%", height: "100%", hash: "hash-bd9c1864")
        ]),
]

/// `generatePreset(1, 'wide', …)` executed in TypeScript: the six wide
/// groups with their layouts and hashes.
private let wideGroups: [ExpectedGroup] = [
    ExpectedGroup(
        name: "vertical 3-split",
        layouts: [
            ExpectedLayout(
                label: "Left Third", x: "0", y: "0",
                width: "1/3", height: "100%", hash: "hash-255093b3"),
            ExpectedLayout(
                label: "Center Third", x: "1/3", y: "0",
                width: "1/3", height: "100%", hash: "hash-41e74cee"),
            ExpectedLayout(
                label: "Right Third", x: "2/3", y: "0",
                width: "1/3", height: "100%", hash: "hash-23c5168d"),
        ]),
    ExpectedGroup(
        name: "vertical 3-split wide center",
        layouts: [
            ExpectedLayout(
                label: "Left Third", x: "0", y: "0",
                width: "1/4", height: "100%", hash: "hash-27056c52"),
            ExpectedLayout(
                label: "Center Third", x: "1/4", y: "0",
                width: "1/2", height: "100%", hash: "hash-47e419ae"),
            ExpectedLayout(
                label: "Right Third", x: "3/4", y: "0",
                width: "1/4", height: "100%", hash: "hash-0f095e2a"),
        ]),
    ExpectedGroup(
        name: "vertical 3-split wide sides",
        layouts: [
            ExpectedLayout(
                label: "Left Side", x: "0", y: "0",
                width: "20%", height: "100%", hash: "hash-aa342321"),
            ExpectedLayout(
                label: "Center Main", x: "20%", y: "0",
                width: "60%", height: "100%", hash: "hash-caf954c6"),
            ExpectedLayout(
                label: "Right Side", x: "80%", y: "0",
                width: "20%", height: "100%", hash: "hash-76a75b04"),
        ]),
    ExpectedGroup(
        name: "vertical 2-split",
        layouts: [
            ExpectedLayout(
                label: "Left Half", x: "0", y: "0",
                width: "50%", height: "100%", hash: "hash-e1d7a9be"),
            ExpectedLayout(
                label: "Right Half", x: "50%", y: "0",
                width: "50%", height: "100%", hash: "hash-08b184c4"),
        ]),
    ExpectedGroup(
        name: "grid 4x2",
        layouts: [
            ExpectedLayout(
                label: "Top Left 1", x: "0", y: "0",
                width: "25%", height: "50%", hash: "hash-0e05d798"),
            ExpectedLayout(
                label: "Top Left 2", x: "25%", y: "0",
                width: "25%", height: "50%", hash: "hash-d590ab2a"),
            ExpectedLayout(
                label: "Top Right 1", x: "50%", y: "0",
                width: "25%", height: "50%", hash: "hash-7aa183d2"),
            ExpectedLayout(
                label: "Top Right 2", x: "75%", y: "0",
                width: "25%", height: "50%", hash: "hash-7e1fcbaf"),
            ExpectedLayout(
                label: "Bottom Left 1", x: "0", y: "50%",
                width: "25%", height: "50%", hash: "hash-845c4d52"),
            ExpectedLayout(
                label: "Bottom Left 2", x: "25%", y: "50%",
                width: "25%", height: "50%", hash: "hash-94808464"),
            ExpectedLayout(
                label: "Bottom Right 1", x: "50%", y: "50%",
                width: "25%", height: "50%", hash: "hash-38bdd30c"),
            ExpectedLayout(
                label: "Bottom Right 2", x: "75%", y: "50%",
                width: "25%", height: "50%", hash: "hash-55c997a9"),
        ]),
    ExpectedGroup(
        name: "full screen",
        layouts: [
            ExpectedLayout(
                label: "full", x: "0", y: "0",
                width: "100%", height: "100%", hash: "hash-bd9c1864")
        ]),
]

private func expectMatches(
    _ groups: [LayoutGroup], _ expected: [ExpectedGroup],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(groups.map(\.name) == expected.map(\.name), sourceLocation: sourceLocation)
    for (group, expectedGroup) in zip(groups, expected) {
        #expect(
            group.layouts.count == expectedGroup.layouts.count,
            "group \(expectedGroup.name)", sourceLocation: sourceLocation)
        for (layout, pin) in zip(group.layouts, expectedGroup.layouts) {
            #expect(layout.label == pin.label, sourceLocation: sourceLocation)
            #expect(layout.position.x == pin.x, "\(pin.label)", sourceLocation: sourceLocation)
            #expect(layout.position.y == pin.y, "\(pin.label)", sourceLocation: sourceLocation)
            #expect(
                layout.size.width == pin.width, "\(pin.label)",
                sourceLocation: sourceLocation)
            #expect(
                layout.size.height == pin.height, "\(pin.label)",
                sourceLocation: sourceLocation)
            #expect(layout.hash == pin.hash, "\(pin.label)", sourceLocation: sourceLocation)
        }
    }
}

/// Compatibility pins for ``PresetGenerator``.
///
/// The GNOME version has no unit tests for `preset-generator.ts` /
/// `preset-config.ts`, so these expected structures were obtained by
/// executing the actual TypeScript generator (verbatim sources, Node.js v24
/// native type stripping, a sequential UUID stub) for every configuration
/// tested here — they are NOT hand-derived. The layout hashes are persisted
/// in exported collection JSON, so both apps must mint identical values.
@Suite struct PresetGeneratorTests {
    @Suite struct Names {
        @Test func singularAndPluralMonitorNames() {
            #expect(
                PresetGenerator.presetName(monitorCount: 1, monitorType: .standard)
                    == "1 Monitor - Standard")
            #expect(
                PresetGenerator.presetName(monitorCount: 1, monitorType: .wide)
                    == "1 Monitor - Wide")
            #expect(
                PresetGenerator.presetName(monitorCount: 2, monitorType: .standard)
                    == "2 Monitors - Standard")
            #expect(
                PresetGenerator.presetName(monitorCount: 3, monitorType: .wide)
                    == "3 Monitors - Wide")
        }

        @Test func theCollectionIsNamedAfterTheConfiguration() {
            let preset = PresetGenerator.generate(monitorCount: 2, monitorType: .wide)
            #expect(preset.name == "2 Monitors - Wide")
        }
    }

    /// The classic 8 layouts of v0.1: a single standard monitor generates
    /// exactly the groups the fixed `BuiltInPresets` constant used to ship
    /// (which itself pinned the GNOME generator's single-standard-monitor
    /// output) — this suite carries that compatibility statement forward.
    @Suite struct SingleStandardMonitor {
        private let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)

        @Test func matchesTheGnomeGeneratedStructure() {
            expectMatches(primaryGroups(of: preset), standardGroups)
        }

        /// One monitor packs two spaces per row: 4 groups → 2 rows of 2.
        @Test func packsTwoSpacesPerRow() {
            #expect(preset.rows.map(\.spaces.count) == [2, 2])
        }

        @Test func everySpaceTargetsOnlyThePrimaryDisplay() {
            for space in preset.rows.flatMap(\.spaces) {
                #expect(Array(space.displays.keys) == ["0"])
                #expect(space.enabled)
            }
        }

        @Test func everyExpressionParses() throws {
            for group in primaryGroups(of: preset) {
                for layout in group.layouts {
                    _ = try LayoutExpressionParser.parse(layout.position.x)
                    _ = try LayoutExpressionParser.parse(layout.position.y)
                    _ = try LayoutExpressionParser.parse(layout.size.width)
                    _ = try LayoutExpressionParser.parse(layout.size.height)
                }
            }
        }
    }

    @Suite struct SingleWideMonitor {
        private let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .wide)

        @Test func matchesTheGnomeGeneratedStructure() {
            expectMatches(primaryGroups(of: preset), wideGroups)
        }

        /// 6 groups, two spaces per row → 3 rows of 2.
        @Test func packsTwoSpacesPerRow() {
            #expect(preset.rows.map(\.spaces.count) == [2, 2, 2])
        }
    }

    @Suite struct MultipleMonitors {
        /// Multiple monitors get one space per row: 4 standard groups → 4
        /// rows, 6 wide groups → 6 rows.
        @Test func oneSpacePerRow() {
            let standard = PresetGenerator.generate(monitorCount: 2, monitorType: .standard)
            #expect(standard.rows.map(\.spaces.count) == [1, 1, 1, 1])

            let wide = PresetGenerator.generate(monitorCount: 3, monitorType: .wide)
            #expect(wide.rows.map(\.spaces.count) == [1, 1, 1, 1, 1, 1])
        }

        @Test func everySpaceAssignsTheGroupToEveryMonitor() {
            let preset = PresetGenerator.generate(monitorCount: 3, monitorType: .standard)
            for space in preset.rows.flatMap(\.spaces) {
                #expect(space.displays.keys.sorted() == ["0", "1", "2"])
                let names = Set(space.displays.values.map(\.name))
                #expect(names.count == 1, "all displays of a space show the same group")
            }
        }

        /// Each display resolves the group independently, so the same group
        /// on two monitors holds distinct layout ids (exactly like the GNOME
        /// `createSpace` minting a fresh group per monitor).
        @Test func displaysOfASpaceHoldDistinctLayoutIds() throws {
            let preset = PresetGenerator.generate(monitorCount: 2, monitorType: .standard)
            let space = try #require(preset.rows.first?.spaces.first)
            let first = try #require(space.displays["0"]).layouts.map(\.id)
            let second = try #require(space.displays["1"]).layouts.map(\.id)
            #expect(Set(first).isDisjoint(with: Set(second)))
        }

        /// The projection the panel uses (primary display) shows the same
        /// group sequence regardless of monitor count.
        @Test func primaryProjectionMatchesTheSingleMonitorVocabulary() {
            let preset = PresetGenerator.generate(monitorCount: 2, monitorType: .standard)
            expectMatches(primaryGroups(of: preset), standardGroups)
        }
    }

    @Suite struct IdentityMinting {
        /// Ids are freshly minted per call; hashes are derived from the
        /// expressions and therefore stable.
        @Test func idsAreFreshPerCallAndHashesAreStable() throws {
            let first = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)
            let second = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)

            #expect(first.id != second.id)
            #expect(first.rows.flatMap(\.spaces).map(\.id) != second.rows.flatMap(\.spaces).map(\.id))

            let firstLayouts = primaryGroups(of: first).flatMap(\.layouts)
            let secondLayouts = primaryGroups(of: second).flatMap(\.layouts)
            #expect(firstLayouts.map(\.id) != secondLayouts.map(\.id))
            #expect(firstLayouts.map(\.hash) == secondLayouts.map(\.hash))
        }
    }

    /// Exact pixel rects on a representative 1920x1080 work area — the v0.1
    /// compatibility pins carried over from `BuiltInPresetsTests`.
    @Suite struct StandardFramesOn1920x1080 {
        private static let width: Double = 1920
        private static let height: Double = 1080
        private let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)

        @Test func vertical2Split() throws {
            let frames = try resolveFrames(
                of: group(named: "vertical 2-split", in: preset),
                containerWidth: Self.width, containerHeight: Self.height)
            #expect(frames[0].label == "Left Half")
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 960, height: 1080))
            #expect(frames[1].label == "Right Half")
            #expect(frames[1].frame == LayoutFrame(x: 960, y: 0, width: 960, height: 1080))
        }

        @Test func horizontal2Split() throws {
            let frames = try resolveFrames(
                of: group(named: "horizontal 2-split", in: preset),
                containerWidth: Self.width, containerHeight: Self.height)
            #expect(frames[0].label == "Top Half")
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 1920, height: 540))
            #expect(frames[1].label == "Bottom Half")
            #expect(frames[1].frame == LayoutFrame(x: 0, y: 540, width: 1920, height: 540))
        }

        @Test func vertical3Split() throws {
            let frames = try resolveFrames(
                of: group(named: "vertical 3-split", in: preset),
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
                of: group(named: "full screen", in: preset),
                containerWidth: Self.width, containerHeight: Self.height)
            #expect(frames[0].label == "full")
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 1920, height: 1080))
        }
    }

    /// A container whose width is not divisible by three, checking that the
    /// thirds round exactly like the GNOME version (Math.round per component).
    @Suite struct FramesOnIndivisibleContainer {
        @Test func vertical3SplitOn1366x768() throws {
            let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .standard)
            let frames = try resolveFrames(
                of: group(named: "vertical 3-split", in: preset),
                containerWidth: 1366, containerHeight: 768)
            // 1/3 of 1366 = 455.333... -> 455; 2/3 of 1366 = 910.666... -> 911.
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 455, height: 768))
            #expect(frames[1].frame == LayoutFrame(x: 455, y: 0, width: 455, height: 768))
            #expect(frames[2].frame == LayoutFrame(x: 911, y: 0, width: 455, height: 768))
        }
    }

    /// Exact pixel rects for the wide-only groups on a 3440x1440 ultrawide.
    @Suite struct WideFramesOn3440x1440 {
        private static let width: Double = 3440
        private static let height: Double = 1440
        private let preset = PresetGenerator.generate(monitorCount: 1, monitorType: .wide)

        @Test func vertical3SplitWideCenter() throws {
            let frames = try resolveFrames(
                of: group(named: "vertical 3-split wide center", in: preset),
                containerWidth: Self.width, containerHeight: Self.height)
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 860, height: 1440))
            #expect(frames[1].frame == LayoutFrame(x: 860, y: 0, width: 1720, height: 1440))
            #expect(frames[2].frame == LayoutFrame(x: 2580, y: 0, width: 860, height: 1440))
        }

        @Test func vertical3SplitWideSides() throws {
            let frames = try resolveFrames(
                of: group(named: "vertical 3-split wide sides", in: preset),
                containerWidth: Self.width, containerHeight: Self.height)
            #expect(frames[0].frame == LayoutFrame(x: 0, y: 0, width: 688, height: 1440))
            #expect(frames[1].frame == LayoutFrame(x: 688, y: 0, width: 2064, height: 1440))
            #expect(frames[2].frame == LayoutFrame(x: 2752, y: 0, width: 688, height: 1440))
        }

        @Test func grid4x2() throws {
            let frames = try resolveFrames(
                of: group(named: "grid 4x2", in: preset),
                containerWidth: Self.width, containerHeight: Self.height)
            let expected = [
                LayoutFrame(x: 0, y: 0, width: 860, height: 720),
                LayoutFrame(x: 860, y: 0, width: 860, height: 720),
                LayoutFrame(x: 1720, y: 0, width: 860, height: 720),
                LayoutFrame(x: 2580, y: 0, width: 860, height: 720),
                LayoutFrame(x: 0, y: 720, width: 860, height: 720),
                LayoutFrame(x: 860, y: 720, width: 860, height: 720),
                LayoutFrame(x: 1720, y: 720, width: 860, height: 720),
                LayoutFrame(x: 2580, y: 720, width: 860, height: 720),
            ]
            #expect(frames.map(\.frame) == expected)
        }
    }

    /// Every base group parses, including the ones no preset references
    /// (`grid 3x2`) — the configuration is ported verbatim.
    @Suite struct Configuration {
        @Test func everyBaseGroupExpressionParses() throws {
            for group in PresetConfiguration.baseLayoutGroups {
                for layout in group.layouts {
                    _ = try LayoutExpressionParser.parse(layout.x)
                    _ = try LayoutExpressionParser.parse(layout.y)
                    _ = try LayoutExpressionParser.parse(layout.width)
                    _ = try LayoutExpressionParser.parse(layout.height)
                }
            }
        }

        @Test func everyReferencedGroupNameResolves() {
            let names = Set(PresetConfiguration.baseLayoutGroups.map(\.name))
            for name in PresetConfiguration.standardLayoutGroupNames {
                #expect(names.contains(name))
            }
            for name in PresetConfiguration.wideLayoutGroupNames {
                #expect(names.contains(name))
            }
        }
    }
}
