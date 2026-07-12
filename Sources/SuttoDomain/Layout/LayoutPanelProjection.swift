/// Projects a ``SpaceCollection`` onto the flat list of layout groups the
/// v0.2 panel renders (one panel row per group, via ``LayoutPanelGrid``).
///
/// ## Projection rule (v0.2-simple)
///
/// One layout group per **enabled** space, in reading order (rows top to
/// bottom, spaces left to right within a row), taking the group assigned to
/// the primary display (monitor key `"0"`). Enabled spaces without a
/// primary-display assignment are skipped.
///
/// ## Why this mirrors the GNOME panel
///
/// The GNOME main panel filters disabled spaces (`filterEnabledSpaces` in
/// `ui/main-panel/index.ts`) and renders one miniature per remaining space;
/// each miniature draws only the monitors that physically exist
/// (`createMiniatureSpaceView` in `ui/components/miniature-space.ts` skips
/// unknown monitor keys). On a single monitor only key `"0"` exists, so
/// each enabled space effectively contributes exactly its `"0"` layout
/// group — the list this projection produces. The GNOME preset generator
/// creates one space per layout group, so for preset-shaped collections the
/// projection reproduces the familiar group-per-row panel exactly. The v0.3
/// richer panel (miniature space previews, multi-monitor) will replace this
/// projection rather than extend it.
public enum LayoutPanelProjection {
    /// The monitor key of the primary display, matching how both apps key
    /// the first monitor (`"0"`).
    public static let primaryDisplayKey = "0"

    /// The layout groups the panel shows for `collection`, per the
    /// projection rule above. May be empty (e.g. every space disabled),
    /// in which case the panel renders empty — the GNOME panel behaves the
    /// same after filtering.
    public static func layoutGroups(in collection: SpaceCollection) -> [LayoutGroup] {
        collection.rows
            .flatMap(\.spaces)
            .filter(\.enabled)
            .compactMap { $0.displays[primaryDisplayKey] }
    }
}
