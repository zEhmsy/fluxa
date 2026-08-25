import Foundation

// MARK: - SystemStatsInterval

/// How often Fluxa re-samples CPU, GPU, memory and temperatures.
///
/// Unlike `UsageRefreshInterval` nothing here costs a network request — every reading is a local
/// syscall or an IORegistry lookup. What the choice actually buys is a trade between catching short
/// spikes and having a menu bar whose digits sit still long enough to read.
enum SystemStatsInterval: String, CaseIterable, Identifiable, Codable {
    case oneSecond
    case twoSeconds
    case fiveSeconds
    case tenSeconds

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .oneSecond:    return 1
        case .twoSeconds:   return 2
        case .fiveSeconds:  return 5
        case .tenSeconds:   return 10
        }
    }

    var label: String {
        switch self {
        case .oneSecond:    return "Every second"
        case .twoSeconds:   return "Every 2 seconds"
        case .fiveSeconds:  return "Every 5 seconds"
        case .tenSeconds:   return "Every 10 seconds"
        }
    }

    /// Picker help text — what you gain and what you give up.
    var detail: String {
        switch self {
        case .oneSecond:
            return "Catches every spike; the menu bar digits change constantly."
        case .twoSeconds:
            return "Responsive without the numbers flickering."
        case .fiveSeconds:
            return "Steady to read; brief spikes can pass unseen."
        case .tenSeconds:
            return "Shows the trend only — lightest on the CPU it measures."
        }
    }

    static let fallback: SystemStatsInterval = .twoSeconds
}
