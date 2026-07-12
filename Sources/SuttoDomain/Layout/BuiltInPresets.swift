/// The built-in layout presets shipped with v0.1.
///
/// This is the fixed set of layout groups that the GNOME version's preset
/// generator (`operations/layout/preset-generator-operations/preset-generator.ts`)
/// produces for a single standard (16:9-ish) landscape monitor: the groups
/// named by `STANDARD_LAYOUT_GROUP_NAMES` in `domain/settings/preset-config.ts`,
/// with the layout definitions copied verbatim from `BASE_LAYOUT_GROUPS` in
/// the same file. Reproducing that vocabulary keeps the two apps feeling
/// identical and lets v0.2's real preset generator replace this constant as
/// a drop-in upgrade.
public enum BuiltInPresets {
    /// Layout groups for a single standard landscape monitor, in the order
    /// the GNOME version lists them (`STANDARD_LAYOUT_GROUP_NAMES`).
    public static let standardLayoutGroups: [LayoutGroup] = [
        LayoutGroup(
            name: "vertical 2-split",
            layouts: [
                Layout(
                    label: "Left Half",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "50%", height: "100%")
                ),
                Layout(
                    label: "Right Half",
                    position: LayoutPosition(x: "50%", y: "0"),
                    size: LayoutSize(width: "50%", height: "100%")
                ),
            ]
        ),
        LayoutGroup(
            name: "horizontal 2-split",
            layouts: [
                Layout(
                    label: "Top Half",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "100%", height: "50%")
                ),
                Layout(
                    label: "Bottom Half",
                    position: LayoutPosition(x: "0", y: "50%"),
                    size: LayoutSize(width: "100%", height: "50%")
                ),
            ]
        ),
        LayoutGroup(
            name: "vertical 3-split",
            layouts: [
                Layout(
                    label: "Left Third",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "1/3", height: "100%")
                ),
                Layout(
                    label: "Center Third",
                    position: LayoutPosition(x: "1/3", y: "0"),
                    size: LayoutSize(width: "1/3", height: "100%")
                ),
                Layout(
                    label: "Right Third",
                    position: LayoutPosition(x: "2/3", y: "0"),
                    size: LayoutSize(width: "1/3", height: "100%")
                ),
            ]
        ),
        LayoutGroup(
            name: "full screen",
            layouts: [
                Layout(
                    label: "full",
                    position: LayoutPosition(x: "0", y: "0"),
                    size: LayoutSize(width: "100%", height: "100%")
                )
            ]
        ),
    ]
}
