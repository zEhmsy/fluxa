import Foundation

// MARK: - StrokeSmoothing

/// Generates smooth quadratic Bézier curve segments through raw points to eliminate jagged edges.
package enum StrokeSmoothing {

    package struct QuadSegment: Equatable, Sendable {
        package var start: DrawingPoint
        package var control: DrawingPoint
        package var end: DrawingPoint
    }

    /// Converts an array of sampled points into smooth quadratic Bézier curve segments.
    /// Each segment curves from midpoint to midpoint, using the recorded sample as control point.
    package static func smooth(points: [DrawingPoint]) -> [QuadSegment] {
        guard points.count >= 3 else {
            // For 0, 1, or 2 points, no quad curve needed
            return []
        }

        var segments: [QuadSegment] = []
        var currentStart = points[0]

        for i in 1..<(points.count - 1) {
            let control = points[i]
            let next = points[i + 1]
            let midPoint = DrawingPoint(
                x: (control.x + next.x) * 0.5,
                y: (control.y + next.y) * 0.5,
                timestamp: (control.timestamp + next.timestamp) * 0.5
            )

            segments.append(QuadSegment(start: currentStart, control: control, end: midPoint))
            currentStart = midPoint
        }

        // Final segment connecting to the last point
        if let last = points.last {
            segments.append(QuadSegment(
                start: currentStart,
                control: points[points.count - 2],
                end: last
            ))
        }

        return segments
    }
}
