import SuttoDomain

/// Converts an imported ``SuttoDomain/LayoutConfiguration`` into the
/// ``SuttoDomain/SpacesRow`` hierarchy of a ``SuttoDomain/SpaceCollection``,
/// minting the runtime identities the configuration format deliberately
/// omits.
///
/// Faithful port of the conversion half of the GNOME
/// `operations/layout/space-collection-operations/import-collection.ts`
/// (`configurationToSpacesRows` → `settingToSpacesRow` → `settingToSpace`
/// → `settingToLayout`):
///
/// - Every space gets a fresh ``SuttoDomain/SpaceId`` and starts `enabled`.
/// - Every layout gets a fresh ``SuttoDomain/LayoutId`` and its coordinate
///   hash from ``SuttoDomain/generateLayoutHash(x:y:width:height:)`` — this
///   is `Layout.init(label:position:size:)`, the Swift counterpart of
///   `settingToLayout`.
/// - A display referencing a layout-group name that does not exist in
///   `layoutGroups` is skipped with a warning, exactly like the GNOME
///   importer (`continue` after the "not found" log).
/// - Each display resolves the group setting independently, so — again like
///   GNOME — two displays naming the same group get *distinct* layout ids.
public enum ImportConversion {
    /// Builds the rows of the collection-to-be from `configuration`.
    ///
    /// - Parameter warn: receives a message per unresolvable layout-group
    ///   reference; the caller decides where it goes (the import use case
    ///   logs it, tests capture it).
    public static func spacesRows(
        from configuration: LayoutConfiguration,
        warn: (String) -> Void = { _ in }
    ) -> [SpacesRow] {
        configuration.rows.map { rowSetting in
            SpacesRow(
                spaces: rowSetting.spaces.map { spaceSetting in
                    space(from: spaceSetting, groupSettings: configuration.layoutGroups, warn: warn)
                })
        }
    }

    private static func space(
        from setting: SpaceSetting,
        groupSettings: [LayoutGroupSetting],
        warn: (String) -> Void
    ) -> Space {
        var displays: [String: LayoutGroup] = [:]

        // Sorted for deterministic warning order; the resulting dictionary
        // is order-independent anyway.
        for (monitorKey, groupName) in setting.displays.sorted(by: { $0.key < $1.key }) {
            guard let groupSetting = groupSettings.first(where: { $0.name == groupName }) else {
                warn("Layout Group \"\(groupName)\" not found for monitor \(monitorKey)")
                continue
            }
            displays[monitorKey] = layoutGroup(from: groupSetting)
        }

        return Space(id: .generate(), enabled: true, displays: displays)
    }

    private static func layoutGroup(from setting: LayoutGroupSetting) -> LayoutGroup {
        LayoutGroup(
            name: setting.name,
            layouts: setting.layouts.map { layoutSetting in
                Layout(
                    label: layoutSetting.label,
                    position: LayoutPosition(x: layoutSetting.x, y: layoutSetting.y),
                    size: LayoutSize(width: layoutSetting.width, height: layoutSetting.height)
                )
            }
        )
    }
}
