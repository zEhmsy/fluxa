import Foundation

// MARK: - AlertDwellState

package struct AlertDwellState: Sendable {
    package var consecutiveHolding: Int
    package var lastFiredAt: Date?
    package var isCurrentlyFiring: Bool

    package init(
        consecutiveHolding: Int = 0,
        lastFiredAt: Date? = nil,
        isCurrentlyFiring: Bool = false
    ) {
        self.consecutiveHolding = consecutiveHolding
        self.lastFiredAt = lastFiredAt
        self.isCurrentlyFiring = isCurrentlyFiring
    }
}

// MARK: - AlertEvaluator

/// Applies dwell and hysteresis policy to completed system-reading samples.
@MainActor
package final class AlertEvaluator {
    package private(set) var dwellStates: [UUID: AlertDwellState] = [:]
    private let notifier: AlertNotifying

    package init(notifier: AlertNotifying) {
        self.notifier = notifier
    }

    package func evaluate(
        sample: SystemStatsSample,
        thresholds: [AlertThreshold],
        intervalSeconds: TimeInterval
    ) {
        guard intervalSeconds > 0 else { return }
        let dwellSamplesRequired = max(1, Int((Self.dwellSeconds / intervalSeconds).rounded()))

        for threshold in thresholds where threshold.isEnabled {
            guard let value = sample.value(for: threshold.metricID) else {
                dwellStates[threshold.id] = nil
                continue
            }

            var state = dwellStates[threshold.id] ?? AlertDwellState()
            let isHolding = threshold.direction.isCrossed(value: value, limit: threshold.limit)
            let hasCleared = threshold.direction.hasCleared(
                value: value,
                limit: threshold.limit,
                resetBand: Self.resetBand
            )

            if isHolding {
                state.consecutiveHolding += 1
            } else {
                state.consecutiveHolding = 0
            }

            if hasCleared {
                state.isCurrentlyFiring = false
            }

            if state.consecutiveHolding >= dwellSamplesRequired, !state.isCurrentlyFiring {
                state.isCurrentlyFiring = true
                state.lastFiredAt = Date()
                notifier.notify(
                    metricID: threshold.metricID,
                    value: value,
                    limit: threshold.limit
                )
            }

            dwellStates[threshold.id] = state
        }
    }

    package static let dwellSeconds: TimeInterval = 30
    package static let resetBand: Double = 0.10
}
