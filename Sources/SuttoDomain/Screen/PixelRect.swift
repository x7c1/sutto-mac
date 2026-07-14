/// A point in a pixel coordinate space.
///
/// Which coordinate space (AppKit bottom-left or AX top-left; see
/// ``ScreenCoordinateConverter``) is a property of the value's usage, not of
/// the type: functions taking or returning a `PixelPoint` document the space
/// they expect.
public struct PixelPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// An axis-aligned rectangle in a pixel coordinate space.
///
/// Like ``PixelPoint``, the coordinate space (AppKit bottom-left or AX
/// top-left) is documented at each usage site. `origin` is the corner with
/// the minimal coordinates in AppKit space and the top-left corner in AX
/// space; both interpretations store the same `(x, y, width, height)`
/// numbers, which is what lets ``ScreenCoordinateConverter`` translate
/// between them by flipping `y` alone.
public struct PixelRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The largest x coordinate covered by the rectangle.
    public var maxX: Double { x + width }

    /// The largest y coordinate covered by the rectangle.
    public var maxY: Double { y + height }

    /// The center of the rectangle.
    public var center: PixelPoint {
        PixelPoint(x: x + width / 2, y: y + height / 2)
    }

    /// Whether `point` lies inside the rectangle.
    ///
    /// Containment is half-open (`[minX, maxX) × [minY, maxY)`) so that a
    /// point on the shared edge of two adjacent screens belongs to exactly
    /// one of them.
    public func contains(_ point: PixelPoint) -> Bool {
        point.x >= x && point.x < maxX && point.y >= y && point.y < maxY
    }

    /// The Euclidean distance from `point` to the nearest part of the
    /// rectangle.
    ///
    /// `0` when the point is inside *or on the boundary* (unlike the
    /// half-open ``contains(_:)``, which excludes the `maxX`/`maxY` edges):
    /// a point sitting exactly on an outer edge is distance `0` from that
    /// rectangle, which is what lets screen selection resolve such a point
    /// to its own screen rather than a farther one. Otherwise it is the
    /// length of the shortest segment from the point to the rectangle,
    /// using the standard clamped per-axis deltas.
    public func distance(to point: PixelPoint) -> Double {
        let dx = max(x - point.x, 0, point.x - maxX)
        let dy = max(y - point.y, 0, point.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
