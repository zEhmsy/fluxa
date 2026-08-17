import Foundation

// MARK: - AgentUsageMetric

/// One quota window of one AI coding agent — Claude's 5-hour session, Codex's weekly limit, and so on.
///
/// Percentages come straight from each provider's own usage endpoint (the same one its CLI reads),
/// so nothing here is estimated from local logs.
struct AgentUsageMetric: Identifiable, Hashable {
    /// Stable "agent.window" id (e.g. "claude.session") — the key persisted in AppSettings.
    let id: String
    let providerID: String
    /// Agent name for display ("Claude", "Codex").
    let providerName: String
    /// Human label for the window ("Session", "Weekly", "Sonnet").
    let label: String
    /// Share of the quota already used, 0...100.
    let percentUsed: Int
    /// When this window rolls over, if the provider reports it.
    let resetsAt: Date?

    /// 0...1 fill for the meter.
    var fraction: Double { Double(percentUsed) / 100.0 }

    /// Severity bands for the meter color — the thresholds a user reads as
    /// "fine / getting close / about to run out".
    enum Severity {
        case normal, warning, critical
    }

    var severity: Severity {
        switch percentUsed {
        case ..<75: return .normal
        case ..<90: return .warning
        default: return .critical
        }
    }

    /// Compact reset note for the tooltip ("resets in 2h 45m"), or nil when unknown or already past.
    func resetNote(now: Date = Date()) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        let seconds = Int(resetsAt.timeIntervalSince(now))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 { return "resets in \(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }
}
