import Foundation

// MARK: - ArrowGeometry

/// Computes sharp arrowhead geometry and shaft endpoints given start and end coordinates.
package enum ArrowGeometry {

    package struct ArrowShape: Equatable, Sendable {
        package var shaftStart: DrawingPoint
        package var shaftEnd: DrawingPoint
        package var headTip: DrawingPoint
        package var headLeft: DrawingPoint
        package var headRight: DrawingPoint

        package var headPolygon: [DrawingPoint] {
            [headTip, headLeft, headRight]
        }
    }

    /// Computes the arrow geometry.
    /// - Parameters:
    ///   - start: Starting coordinate of the arrow.
    ///   - end: Ending coordinate (where the arrow head points).
    ///   - lineWidth: Stroke thickness used to scale the arrow head proportionally.
    ///   - headAngle: Angular aperture of the arrowhead wings (default: 30° = π / 6).
    package static func compute(
        start: DrawingPoint,
        end: DrawingPoint,
        lineWidth: Double,
        headAngle: Double = .pi / 6.0
    ) -> ArrowShape? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()

        // Too short to render a sensible arrow
        guard length >= 3.0 else { return nil }

        let angle = atan2(dy, dx)
        let baseHeadLength = max(14.0, lineWidth * 3.5)
        let headLength = min(baseHeadLength, length * 0.5)

        let leftX = end.x - headLength * cos(angle - headAngle)
        let leftY = end.y - headLength * sin(angle - headAngle)

        let rightX = end.x - headLength * cos(angle + headAngle)
        let rightY = end.y - headLength * sin(angle + headAngle)

        return ArrowShape(
            shaftStart: start,
            shaftEnd: end,
            headTip: end,
            headLeft: DrawingPoint(x: leftX, y: leftY),
            headRight: DrawingPoint(x: rightX, y: rightY)
        )
    }
}
