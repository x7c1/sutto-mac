/// Decides whether a point lies within a threshold distance of any of the
/// four edges of a rectangle.
///
/// The macOS port of the GNOME version's `EdgeDetector`
/// (`src/domain/geometry/edge-detector.ts`), re-expressed against the
/// domain's own ``PixelPoint`` / ``PixelRect`` value types.
///
/// The detector is **coordinate-space agnostic**: it compares the raw
/// numbers it is handed and does not care whether they are AppKit
/// bottom-left or AX top-left coordinates (see ``ScreenCoordinateConverter``).
/// The caller feeds a point and a rectangle in the *same* space — the edge
/// tests are symmetric across all four sides, so the result is identical in
/// either space. The two "vertical" sides are described here as top/bottom
/// for readability, but no orientation assumption is baked in.
public struct EdgeDetector: Equatable, Sendable {
    /// Distance in pixels from an edge within which a point counts as being
    /// "at" that edge. Mirrors the GNOME version's `EDGE_THRESHOLD = 10`
    /// (`src/composition/controller.ts`).
    public static let defaultThreshold: Double = 10

    /// How close (in pixels) a point must be to an edge to count as being at
    /// it.
    public let threshold: Double

    public init(threshold: Double = Self.defaultThreshold) {
        self.threshold = threshold
    }

    /// Whether `point` is within ``threshold`` of any of the four edges of
    /// `rect`.
    ///
    /// Ported rule for rule from GNOME's `isAtEdge`: a point counts as at an
    /// edge when it is on the inner side of the edge line but no farther than
    /// `threshold` from it. The four tests use `<=` on the low sides and
    /// `>=` on the high sides so that a point sitting exactly on an edge
    /// always qualifies.
    public func isAtEdge(_ point: PixelPoint, of rect: PixelRect) -> Bool {
        let atMinX = point.x <= rect.x + threshold
        let atMaxX = point.x >= rect.maxX - threshold
        let atMinY = point.y <= rect.y + threshold
        let atMaxY = point.y >= rect.maxY - threshold
        return atMinX || atMaxX || atMinY || atMaxY
    }
}
