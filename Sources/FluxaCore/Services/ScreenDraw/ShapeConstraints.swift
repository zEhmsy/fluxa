import Foundation

// MARK: - ShapeConstraints

/// Mathematical helpers for shape snapping when Shift is held.
package enum ShapeConstraints {

    /// Snaps an endpoint relative to a start point according to the tool:
    /// - Lines and arrows snap to 45° increments (0°, 45°, 90°, 135°, etc.).
    /// - Rectangles snap to squares (equal width and height).
    /// - Ellipses snap to circles.
    package static func snap(
        start: DrawingPoint,
        current: DrawingPoint,
        tool: ScreenDrawTool
    ) -> DrawingPoint {
        let dx = current.x - start.x
        let dy = current.y - start.y

        switch tool {
        case .line, .arrow:
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance > 0.001 else { return current }
            let angle = atan2(dy, dx)
            let step = Double.pi / 4.0 // 45 degrees
            let snappedAngle = (angle / step).rounded() * step
            return DrawingPoint(
                x: start.x + distance * cos(snappedAngle),
                y: start.y + distance * sin(snappedAngle)
            )

        case .rectangle, .ellipse:
            let side = max(abs(dx), abs(dy))
            let signX = dx >= 0 ? 1.0 : -1.0
            let signY = dy >= 0 ? 1.0 : -1.0
            return DrawingPoint(
                x: start.x + signX * side,
                y: start.y + signY * side
            )

        default:
            return current
        }
    }
}
