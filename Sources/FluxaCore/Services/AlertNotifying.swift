import Foundation

// MARK: - AlertNotifying

package protocol AlertNotifying: Sendable {
    func notify(metricID: SystemMetricID, value: Double, limit: Double)
}
