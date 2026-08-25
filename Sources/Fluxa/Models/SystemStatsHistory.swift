import Foundation

// MARK: - SystemStatsHistorySample

/// One timestamped pass over the system sensors, kept in memory for the dashboard charts.
///
/// Values are deliberately sparse. A source that misses one pass does not inherit its previous
/// reading here: the live strip may hold the last good value for continuity, but a chart should
/// show a gap rather than manufacture a flat segment that was never measured.
struct SystemStatsHistorySample: Identifiable, Sendable {
    let timestamp: Date
    let values: [SystemMetricID: Double]

    var id: Date { timestamp }

    func value(for id: SystemMetricID) -> Double? {
        values[id]
    }
}
