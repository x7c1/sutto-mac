/// Generates the preset ``SpaceCollection`` for a monitor configuration.
///
/// Faithful port of `generatePreset` in the GNOME
/// `operations/layout/preset-generator-operations/preset-generator.ts`
/// (it lives in the domain here because it is pure — the trigger and
/// persistence around it are the operations layer's job):
///
/// - The collection is named after the configuration
///   (``presetName(monitorCount:monitorType:)``).
/// - The group list is ``SuttoDomain/PresetConfiguration/wideLayoutGroupNames``
///   or ``SuttoDomain/PresetConfiguration/standardLayoutGroupNames`` by
///   monitor type; names that resolve to no base group are skipped.
/// - One space per layout group. A single monitor packs two spaces per row;
///   multiple monitors get one space per row (`spacesPerRow` in the GNOME
///   `generateRows`).
/// - Every space assigns the group to *every* monitor key `"0"..<count`,
///   resolving the group setting independently per display, so two displays
///   showing the same group hold distinct layout ids (`createSpace` calling
///   `createLayoutGroup` per monitor).
/// - Ids are minted fresh on every call; layout hashes come from the
///   position/size expressions (`Layout.init(label:position:size:)`, the
///   counterpart of `createLayout`), so they are stable across calls.
public enum PresetGenerator {
    /// The preset name for a monitor configuration, mirroring
    /// `getPresetName`: `"1 Monitor - Standard"`, `"2 Monitors - Wide"`, …
    public static func presetName(monitorCount: Int, monitorType: MonitorType) -> String {
        let suffix = monitorCount == 1 ? "Monitor" : "Monitors"
        let typeLabel = monitorType == .wide ? "Wide" : "Standard"
        return "\(monitorCount) \(suffix) - \(typeLabel)"
    }

    /// Generates the preset collection for `monitorCount` monitors of
    /// `monitorType`, with freshly minted collection, space, and layout ids.
    public static func generate(monitorCount: Int, monitorType: MonitorType) -> SpaceCollection {
        SpaceCollection(
            id: .generate(),
            name: presetName(monitorCount: monitorCount, monitorType: monitorType),
            rows: rows(monitorCount: monitorCount, monitorType: monitorType)
        )
    }

    private static func rows(monitorCount: Int, monitorType: MonitorType) -> [SpacesRow] {
        let groupNames =
            monitorType == .wide
            ? PresetConfiguration.wideLayoutGroupNames
            : PresetConfiguration.standardLayoutGroupNames
        let spacesPerRow = monitorCount == 1 ? 2 : 1

        var rows: [SpacesRow] = []
        for chunkStart in stride(from: 0, to: groupNames.count, by: spacesPerRow) {
            let chunk = groupNames[chunkStart..<min(chunkStart + spacesPerRow, groupNames.count)]
            let spaces = chunk.compactMap { name -> Space? in
                guard
                    let groupSetting = PresetConfiguration.baseLayoutGroups
                        .first(where: { $0.name == name })
                else { return nil }
                return space(from: groupSetting, monitorCount: monitorCount)
            }
            if !spaces.isEmpty {
                rows.append(SpacesRow(spaces: spaces))
            }
        }
        return rows
    }

    private static func space(from groupSetting: LayoutGroupSetting, monitorCount: Int) -> Space {
        var displays: [String: LayoutGroup] = [:]
        for monitor in 0..<monitorCount {
            displays[String(monitor)] = layoutGroup(from: groupSetting)
        }
        return Space(id: .generate(), enabled: true, displays: displays)
    }

    private static func layoutGroup(from setting: LayoutGroupSetting) -> LayoutGroup {
        LayoutGroup(
            name: setting.name,
            layouts: setting.layouts.map { layout in
                Layout(
                    label: layout.label,
                    position: LayoutPosition(x: layout.x, y: layout.y),
                    size: LayoutSize(width: layout.width, height: layout.height)
                )
            }
        )
    }
}
