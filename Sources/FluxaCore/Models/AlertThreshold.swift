import Foundation

// MARK: - AlertThreshold

/// One configured boundary for a system reading.
package struct AlertThreshold: Codable, Identifiable, Sendable, Equatable {
    package let id: UUID
    package var metricID: SystemMetricID
    package var direction: Direction
    package var limit: Double
    package var isEnabled: Bool

    package enum Direction: String, Codable, Sendable {
        case above
        case below
    }

    package init(
        id: UUID = UUID(),
        metricID: SystemMetricID,
        direction: Direction,
        limit: Double,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.metricID = metricID
        self.direction = direction
        self.limit = limit
        self.isEnabled = isEnabled
    }
}

package extension AlertThreshold {
    static let defaults: [AlertThreshold] = [
        AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 90, isEnabled: false),
        AlertThreshold(metricID: .dieTemperature, direction: .above, limit: 90, isEnabled: false),
        AlertThreshold(
            metricID: .diskFreeSpace,
            direction: .below,
            limit: 5 * 1024 * 1024 * 1024,
            isEnabled: false
        ),
    ]
}

package extension AlertThreshold.Direction {
    func isCrossed(value: Double, limit: Double) -> Bool {
        switch self {
        case .above: return value >= limit
        case .below: return value <= limit
        }
    }

    func hasCleared(value: Double, limit: Double, resetBand: Double) -> Bool {
        switch self {
        case .above: return value < limit * (1 - resetBand)
        case .below: return value > limit * (1 + resetBand)
        }
    }
}
