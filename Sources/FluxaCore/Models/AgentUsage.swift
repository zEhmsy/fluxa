import Foundation

// MARK: - AgentUsageMetric

/// One quota window of one AI coding agent — Claude's 5-hour session, Codex's weekly limit, and so on.
///
/// Percentages come straight from each provider's own usage endpoint (the same one its CLI reads),
/// so nothing here is estimated from local logs.
package struct AgentUsageMetric: Identifiable, Hashable {
    /// Stable "agent.window" id (e.g. "claude.session") — the key persisted in AppSettings.
    package let id: String
    package let providerID: String
    /// Agent name for display ("Claude", "Codex").
    package let providerName: String
    /// Human label for the window ("Session", "Weekly", "Sonnet").
    package let label: String
    /// Share of the quota already used, 0...100.
    package let percentUsed: Int
    /// When this window rolls over, if the provider reports it.
    let resetsAt: Date?

    package init(
        id: String,
        providerID: String,
        providerName: String,
        label: String,
        percentUsed: Int,
        resetsAt: Date?
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.label = label
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
    }

    /// 0...1 fill for the meter.
    package var fraction: Double { Double(percentUsed) / 100.0 }

    /// Severity bands for the meter color — the thresholds a user reads as
    /// "fine / getting close / about to run out".
    package enum Severity {
        case normal, warning, critical
    }

    package var severity: Severity {
        switch percentUsed {
        case ..<75: return .normal
        case ..<90: return .warning
        default: return .critical
        }
    }

    /// A reset further out than this is not a quota window, it's a bad timestamp. Capping the
    /// interval keeps `Int(_:)` below its trapping range no matter what an endpoint sends, and the
    /// note it produces ("resets in 3650d 0h") reads as obviously wrong rather than crashing.
    private static let maximumResetInterval: TimeInterval = 3650 * 24 * 60 * 60
    /// Compact reset note for the tooltip ("resets in 2h 45m"), or nil when unknown or already past.
    package func resetNote(now: Date = Date()) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        // Clamped in `Double` space, before the conversion: `Int(_: Double)` traps outside `Int`'s
        // range, so an absurd `resetsAt` — which every provider's parser can produce from an epoch
        // number it was handed — would otherwise crash the app from a tooltip.
        let interval = min(resetsAt.timeIntervalSince(now), Self.maximumResetInterval)
        let seconds = Int(interval)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 { return "resets in \(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }
}
