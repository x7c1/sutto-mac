/// The button arrangement the layout panel displays: one row per layout
/// group, one button per layout, in the order the groups declare.
///
/// v0.1 shows this flat grid directly. v0.3's richer panel (miniature space
/// previews, keyboard navigation) will grow this model rather than moving
/// arrangement logic into AppKit code.
public struct LayoutPanelGrid: Equatable, Sendable {
    /// One horizontal row of layout buttons, corresponding to one
    /// ``LayoutGroup``.
    public struct Row: Equatable, Sendable {
        /// Name of the group this row was built from.
        public let groupName: String

        /// The layouts shown as buttons in this row, in display order.
        public let layouts: [Layout]

        init(groupName: String, layouts: [Layout]) {
            self.groupName = groupName
            self.layouts = layouts
        }
    }

    /// The rows to render, top to bottom.
    public let rows: [Row]

    /// Builds the grid from layout groups, skipping groups that have no
    /// layouts (an empty row would render as a blank line in the panel).
    public init(groups: [LayoutGroup]) {
        rows = groups
            .filter { !$0.layouts.isEmpty }
            .map { Row(groupName: $0.name, layouts: $0.layouts) }
    }
}
