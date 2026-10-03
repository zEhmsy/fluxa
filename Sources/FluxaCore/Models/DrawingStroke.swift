import Foundation

// MARK: - DrawingPoint

/// Single 2D coordinate sampled during drawing.
package struct DrawingPoint: Codable, Equatable, Sendable, Hashable {
    package var x: Double
    package var y: Double
    package var timestamp: TimeInterval

    package init(x: Double, y: Double, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.x = x
        self.y = y
        self.timestamp = timestamp
    }

    package func distance(to other: DrawingPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - DrawingStroke

/// Complete stroke or geometric shape drawn on screen.
package struct DrawingStroke: Identifiable, Codable, Equatable, Sendable {
    package let id: UUID
    package var tool: ScreenDrawTool
    package var points: [DrawingPoint]
    package var color: ScreenDrawColor
    package var lineWidth: Double
    package var opacity: Double
    package var createdAt: Date
    package var text: String?
    package var textBoundsWidth: Double?
    package var textBoundsHeight: Double?

    package init(
        id: UUID = UUID(),
        tool: ScreenDrawTool,
        points: [DrawingPoint],
        color: ScreenDrawColor,
        lineWidth: Double = 4.0,
        opacity: Double = 1.0,
        createdAt: Date = Date(),
        text: String? = nil,
        textBoundsWidth: Double? = nil,
        textBoundsHeight: Double? = nil
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = max(1.0, lineWidth)
        self.opacity = min(max(opacity, 0.0), 1.0)
        self.createdAt = createdAt
        self.text = text
        self.textBoundsWidth = textBoundsWidth
        self.textBoundsHeight = textBoundsHeight
    }

    /// Whether this stroke has exceeded the disappearing ink duration.
    package func isExpired(at date: Date, timeout: TimeInterval) -> Bool {
        guard timeout > 0 else { return false }
        return date.timeIntervalSince(createdAt) >= timeout
    }

    /// Remaining opacity ratio for fading strokes (1.0 = fully opaque, 0.0 = expired).
    package func fadeAlpha(at date: Date, timeout: TimeInterval, fadeWindow: TimeInterval = 1.0) -> Double {
        guard timeout > 0 else { return opacity }
        let elapsed = date.timeIntervalSince(createdAt)
        if elapsed >= timeout { return 0.0 }
        let fadeStart = max(0.0, timeout - fadeWindow)
        if elapsed <= fadeStart {
            return opacity
        }
        let progress = (elapsed - fadeStart) / (timeout - fadeStart)
        return opacity * (1.0 - progress)
    }

    /// Tests if a point hits any segment of this stroke within a given threshold distance (useful for eraser).
    package func contains(point target: DrawingPoint, threshold: Double) -> Bool {
        guard !points.isEmpty else { return false }

        // Text strokes: hit test against entire bounding rectangle
        if tool == .text, let origin = points.first, let w = textBoundsWidth, let h = textBoundsHeight {
            let minX = origin.x - threshold
            let maxX = origin.x + w + threshold
            let minY = origin.y - threshold
            let maxY = origin.y + h + threshold
            if target.x >= minX && target.x <= maxX && target.y >= minY && target.y <= maxY {
                return true
            }
        }

        if points.count == 1 {
            return points[0].distance(to: target) <= threshold + lineWidth / 2
        }
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            if distanceToSegment(p: target, a: start, b: end) <= threshold + lineWidth / 2 {
                return true
            }
        }
        return false
    }

    private func distanceToSegment(p: DrawingPoint, a: DrawingPoint, b: DrawingPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSq = dx * dx + dy * dy
        if lengthSq == 0 { return p.distance(to: a) }
        let t = max(0.0, min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq))
        let projection = DrawingPoint(x: a.x + t * dx, y: a.y + t * dy)
        return p.distance(to: projection)
    }
}
