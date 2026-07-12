/// Extract all layout IDs from a list of ``SpaceCollection``s.
///
/// Mirrors `extractLayoutIds` in `domain/layout/extract-layout-ids.ts` of
/// the GNOME version. The TypeScript original returns a `ValueSet`, a set
/// keyed by `toString()` because JS classes compare by reference; Swift's
/// `LayoutId` is a `Hashable` value type, so a plain `Set` has exactly the
/// same identity semantics.
public func extractLayoutIds(from collections: [SpaceCollection]) -> Set<LayoutId> {
    var ids: Set<LayoutId> = []

    for collection in collections {
        for row in collection.rows {
            for space in row.spaces {
                for layoutGroup in space.displays.values {
                    for layout in layoutGroup.layouts {
                        ids.insert(layout.id)
                    }
                }
            }
        }
    }

    return ids
}
