import Foundation

// MARK: - UsageRefreshInterval

/// How often Fluxa re-reads agent quotas in the background.
///
/// The choices are derived from what the data can actually express, not picked round-number style.
/// A 5-hour session window spends 100 percentage points over 300 minutes, so at a steady burn
/// **one percentage point takes three minutes** — polling faster than that cannot return a different
/// integer, it only spends requests. Three minutes is therefore the floor, five is a comfortable
/// default (≈1.7 points of movement between reads), and the longer options exist for people who
/// mostly care about the weekly window, where a point takes about 100 minutes.
enum UsageRefreshInterval: String, CaseIterable, Identifiable, Codable {
    case manual
    case threeMinutes
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case hourly

    var id: String { rawValue }

    /// Seconds between background reads; nil means no background reads at all.
    var seconds: TimeInterval? {
        switch self {
        case .manual:         return nil
        case .threeMinutes:   return 180
        case .fiveMinutes:    return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes:  return 1800
        case .hourly:         return 3600
        }
    }

    var label: String {
        switch self {
        case .manual:         return "Only when opened"
        case .threeMinutes:   return "Every 3 minutes"
        case .fiveMinutes:    return "Every 5 minutes"
        case .fifteenMinutes: return "Every 15 minutes"
        case .thirtyMinutes:  return "Every 30 minutes"
        case .hourly:         return "Every hour"
        }
    }

    /// What each choice means in terms of the numbers, shown as the picker's help text.
    var detail: String {
        switch self {
        case .manual:
            return "Reads only when you open the popover — the menu bar can lag behind."
        case .threeMinutes:
            return "The fastest that can show a new number on a 5-hour window."
        case .fiveMinutes:
            return "About 1.7% of a session window between reads."
        case .fifteenMinutes:
            return "About 5% of a session window between reads."
        case .thirtyMinutes:
            return "About 10% of a session window between reads."
        case .hourly:
            return "Enough for weekly limits, coarse for a session."
        }
    }

    static let fallback: UsageRefreshInterval = .fiveMinutes
}
