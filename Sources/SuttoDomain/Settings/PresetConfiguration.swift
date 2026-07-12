/// The layout vocabulary the preset generator draws from.
///
/// Faithful port of `domain/settings/preset-config.ts` of the GNOME version:
/// the same group names, layout labels, and position/size expressions,
/// expressed as ``LayoutGroupSetting`` values (the same configuration types
/// the import format uses — GNOME shares them the same way). The data must
/// stay byte-identical to the GNOME file: the layout hashes minted from
/// these expressions are persisted and compared across the two apps.
public enum PresetConfiguration {
    /// Base layout group definitions, mirroring `BASE_LAYOUT_GROUPS`.
    ///
    /// These are reusable layout configurations referenced by name from
    /// ``wideLayoutGroupNames`` and ``standardLayoutGroupNames``. Some
    /// groups (e.g. `grid 3x2`) are defined but referenced by neither list,
    /// exactly like the GNOME file — they stay for parity, not dead-code
    /// cleanup.
    public static let baseLayoutGroups: [LayoutGroupSetting] = [
        LayoutGroupSetting(
            name: "vertical 2-split",
            layouts: [
                LayoutSetting(label: "Left Half", x: "0", y: "0", width: "50%", height: "100%"),
                LayoutSetting(label: "Right Half", x: "50%", y: "0", width: "50%", height: "100%"),
            ]
        ),
        LayoutGroupSetting(
            name: "horizontal 2-split",
            layouts: [
                LayoutSetting(label: "Top Half", x: "0", y: "0", width: "100%", height: "50%"),
                LayoutSetting(label: "Bottom Half", x: "0", y: "50%", width: "100%", height: "50%"),
            ]
        ),
        LayoutGroupSetting(
            name: "vertical 3-split",
            layouts: [
                LayoutSetting(label: "Left Third", x: "0", y: "0", width: "1/3", height: "100%"),
                LayoutSetting(label: "Center Third", x: "1/3", y: "0", width: "1/3", height: "100%"),
                LayoutSetting(label: "Right Third", x: "2/3", y: "0", width: "1/3", height: "100%"),
            ]
        ),
        LayoutGroupSetting(
            name: "vertical 3-split wide center",
            layouts: [
                LayoutSetting(label: "Left Third", x: "0", y: "0", width: "1/4", height: "100%"),
                LayoutSetting(label: "Center Third", x: "1/4", y: "0", width: "1/2", height: "100%"),
                LayoutSetting(label: "Right Third", x: "3/4", y: "0", width: "1/4", height: "100%"),
            ]
        ),
        LayoutGroupSetting(
            name: "vertical 3-split wide sides",
            layouts: [
                LayoutSetting(label: "Left Side", x: "0", y: "0", width: "20%", height: "100%"),
                LayoutSetting(label: "Center Main", x: "20%", y: "0", width: "60%", height: "100%"),
                LayoutSetting(label: "Right Side", x: "80%", y: "0", width: "20%", height: "100%"),
            ]
        ),
        LayoutGroupSetting(
            name: "grid 3x2",
            layouts: [
                LayoutSetting(label: "Top Left", x: "0", y: "0", width: "1/3", height: "50%"),
                LayoutSetting(label: "Top Center", x: "1/3", y: "0", width: "1/3", height: "50%"),
                LayoutSetting(label: "Top Right", x: "2/3", y: "0", width: "1/3", height: "50%"),
                LayoutSetting(label: "Bottom Left", x: "0", y: "50%", width: "1/3", height: "50%"),
                LayoutSetting(label: "Bottom Center", x: "1/3", y: "50%", width: "1/3", height: "50%"),
                LayoutSetting(label: "Bottom Right", x: "2/3", y: "50%", width: "1/3", height: "50%"),
            ]
        ),
        LayoutGroupSetting(
            name: "grid 4x2",
            layouts: [
                LayoutSetting(label: "Top Left 1", x: "0", y: "0", width: "25%", height: "50%"),
                LayoutSetting(label: "Top Left 2", x: "25%", y: "0", width: "25%", height: "50%"),
                LayoutSetting(label: "Top Right 1", x: "50%", y: "0", width: "25%", height: "50%"),
                LayoutSetting(label: "Top Right 2", x: "75%", y: "0", width: "25%", height: "50%"),
                LayoutSetting(label: "Bottom Left 1", x: "0", y: "50%", width: "25%", height: "50%"),
                LayoutSetting(label: "Bottom Left 2", x: "25%", y: "50%", width: "25%", height: "50%"),
                LayoutSetting(label: "Bottom Right 1", x: "50%", y: "50%", width: "25%", height: "50%"),
                LayoutSetting(label: "Bottom Right 2", x: "75%", y: "50%", width: "25%", height: "50%"),
            ]
        ),
        LayoutGroupSetting(
            name: "full screen",
            layouts: [
                LayoutSetting(label: "full", x: "0", y: "0", width: "100%", height: "100%")
            ]
        ),
    ]

    /// Group names for wide monitors (aspect ratio ≥ 21:9), mirroring
    /// `WIDE_LAYOUT_GROUP_NAMES`.
    public static let wideLayoutGroupNames = [
        "vertical 3-split",
        "vertical 3-split wide center",
        "vertical 3-split wide sides",
        "vertical 2-split",
        "grid 4x2",
        "full screen",
    ]

    /// Group names for standard monitors (16:9 and similar), mirroring
    /// `STANDARD_LAYOUT_GROUP_NAMES`.
    public static let standardLayoutGroupNames = [
        "vertical 2-split",
        "horizontal 2-split",
        "vertical 3-split",
        "full screen",
    ]
}
