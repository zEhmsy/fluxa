import Foundation

// MARK: - SystemMetricID

/// The system readings Fluxa can show: processor and graphics load, their temperatures, and memory
/// footprint.
///
/// The raw values double as the persisted ids in `AppSettings`, so they are spelled out rather than
/// derived from the case names — renaming a case must not silently drop a user's selection.
enum SystemMetricID: String, CaseIterable, Identifiable, Codable, Sendable {
    case cpuUsage        = "system.cpu"
    case gpuUsage        = "system.gpu"
    case memoryUsage     = "system.memory"
    case cpuTemperature  = "system.cpuTemp"
    case gpuTemperature  = "system.gpuTemp"
    case dieTemperature  = "system.dieTemp"

    var id: String { rawValue }

    /// The temperature readings, which are the ones a given Mac may or may not be able to separate.
    static let temperatures: [SystemMetricID] = [.cpuTemperature, .gpuTemperature, .dieTemperature]

    /// What the reading measures — decides both the unit and where the severity bands sit.
    enum Kind {
        /// 0…100, shown as "42%".
        case percentage
        /// Degrees Celsius, shown as "58°".
        case temperature
    }

    var kind: Kind {
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage:
            return .percentage
        case .cpuTemperature, .gpuTemperature, .dieTemperature:
            return .temperature
        }
    }

    /// Full name, used in Customize.
    var title: String {
        switch self {
        case .cpuUsage:         return "CPU Usage"
        case .gpuUsage:         return "GPU Usage"
        case .memoryUsage:      return "Memory Usage"
        case .cpuTemperature:   return "CPU Temperature"
        case .gpuTemperature:   return "GPU Temperature"
        case .dieTemperature:   return "Die Temperature"
        }
    }

    /// Three-or-fewer characters for the popover chip, where the glyph already carries most of the
    /// meaning and the width belongs to the number.
    var shortLabel: String {
        switch self {
        case .cpuUsage:         return "CPU"
        case .gpuUsage:         return "GPU"
        case .memoryUsage:      return "RAM"
        case .cpuTemperature:   return "CPU"
        case .gpuTemperature:   return "GPU"
        case .dieTemperature:   return "DIE"
        }
    }

    /// SF Symbol leading the chip and the menu bar segment. Temperatures use the thermometer rather
    /// than the component glyph: in the menu bar "cpu 42%" and "cpu 58°" would otherwise differ only
    /// by a degree sign.
    var symbolName: String {
        switch self {
        case .cpuUsage:         return "cpu"
        case .gpuUsage:         return "cpu.fill"
        case .memoryUsage:      return "memorychip"
        case .cpuTemperature:   return "thermometer.medium"
        case .gpuTemperature:   return "thermometer.high"
        case .dieTemperature:   return "thermometer.medium"
        }
    }

    /// Why a reading may be missing, shown in Customize instead of leaving the row silently absent.
    var unavailableNote: String {
        switch self {
        case .cpuUsage, .memoryUsage:
            return "Not readable on this Mac."
        case .gpuUsage:
            return "No GPU performance counters on this Mac."
        case .cpuTemperature, .gpuTemperature:
            return "This Mac doesn't label its thermal sensors per component."
        case .dieTemperature:
            return "No usable thermal sensors on this Mac."
        }
    }
}

// MARK: - SystemMetric

/// One resolved reading. Mirrors `AgentUsageMetric`'s shape — a fraction for the meter and a
/// severity for the color — so the popover strip and the menu bar renderer treat system readings and
/// agent quotas the same way.
struct SystemMetric: Identifiable, Hashable, Sendable {

    let id: SystemMetricID

    /// Percent for `.percentage` metrics, degrees Celsius for `.temperature`.
    let value: Double

    /// What goes next to the glyph: "42%" or "58°".
    var displayText: String {
        switch id.kind {
        case .percentage:   return "\(Int(value.rounded()))%"
        case .temperature:  return "\(Int(value.rounded()))°"
        }
    }

    /// 0…1 fill for the meter. Temperatures are mapped across the 30…100 °C band that a laptop
    /// actually moves through — anchoring the bar at 0 °C would leave it nearly static.
    var fraction: Double {
        switch id.kind {
        case .percentage:
            return min(max(value / 100, 0), 1)
        case .temperature:
            return min(max((value - 30) / 70, 0), 1)
        }
    }

    enum Severity {
        case normal, warning, critical
    }

    /// Load and heat need different bands: 90% CPU is normal under a build, 90 °C is not.
    var severity: Severity {
        switch id.kind {
        case .percentage:
            switch value {
            case ..<75:  return .normal
            case ..<90:  return .warning
            default:     return .critical
            }
        case .temperature:
            switch value {
            case ..<70:  return .normal
            case ..<85:  return .warning
            default:     return .critical
            }
        }
    }

    /// Longer form for tooltips and accessibility ("CPU Usage: 42%").
    var tooltip: String { "\(id.title): \(displayText)" }
}
