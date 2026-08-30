import Foundation

// MARK: - SystemMetricID

/// The system readings Fluxa can show: processor and graphics load, their temperatures, and memory
/// footprint.
///
/// The raw values double as the persisted ids in `AppSettings`, so they are spelled out rather than
/// derived from the case names — renaming a case must not silently drop a user's selection.
package enum SystemMetricID: String, CaseIterable, Identifiable, Codable, Sendable {
    case cpuUsage        = "system.cpu"
    case gpuUsage        = "system.gpu"
    case memoryUsage     = "system.memory"
    case cpuTemperature  = "system.cpuTemp"
    case gpuTemperature  = "system.gpuTemp"
    case dieTemperature  = "system.dieTemp"
    case diskUsedPercentage = "system.diskUsed"
    case diskFreeSpace      = "system.diskFree"
    case diskReadRate       = "system.diskRead"
    case diskWriteRate      = "system.diskWrite"
    case networkDownloadRate = "system.netDownload"
    case networkUploadRate   = "system.netUpload"

    package var id: String { rawValue }

    /// The temperature readings, which are the ones a given Mac may or may not be able to separate.
    package static let temperatures: [SystemMetricID] = [.cpuTemperature, .gpuTemperature, .dieTemperature]

    /// What the reading measures — decides both the unit and where the severity bands sit.
    package enum Kind {
        /// 0…100, shown as "42%".
        case percentage
        /// Degrees Celsius, shown as "58°".
        case temperature
        /// Bytes per second, e.g. disk or network throughput. Unbounded.
        case byteRate
        /// Bytes, absolute, e.g. free disk space. Unbounded.
        case byteCount
        /// Seconds, e.g. battery time remaining. Unbounded.
        case duration
    }

    package var kind: Kind {
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage:
            return .percentage
        case .cpuTemperature, .gpuTemperature, .dieTemperature:
            return .temperature
        case .diskUsedPercentage:
            return .percentage
        case .diskFreeSpace:
            return .byteCount
        case .diskReadRate, .diskWriteRate, .networkDownloadRate, .networkUploadRate:
            return .byteRate
        }
    }

    /// Full name, used in Customize.
    package var title: String {
        switch self {
        case .cpuUsage:         return "CPU Usage"
        case .gpuUsage:         return "GPU Usage"
        case .memoryUsage:      return "Memory Usage"
        case .cpuTemperature:   return "CPU Temperature"
        case .gpuTemperature:   return "GPU Temperature"
        case .dieTemperature:   return "Die Temperature"
        case .diskUsedPercentage: return "Disk Used"
        case .diskFreeSpace:      return "Disk Free"
        case .diskReadRate:       return "Disk Read"
        case .diskWriteRate:      return "Disk Write"
        case .networkDownloadRate: return "Download"
        case .networkUploadRate:   return "Upload"
        }
    }

    /// Three-or-fewer characters for the popover chip, where the glyph already carries most of the
    /// meaning and the width belongs to the number.
    package var shortLabel: String {
        switch self {
        case .cpuUsage:         return "CPU"
        case .gpuUsage:         return "GPU"
        case .memoryUsage:      return "RAM"
        case .cpuTemperature:   return "CPU"
        case .gpuTemperature:   return "GPU"
        case .dieTemperature:   return "DIE"
        case .diskUsedPercentage: return "DSK"
        case .diskFreeSpace:      return "FRE"
        case .diskReadRate:       return "R"
        case .diskWriteRate:      return "W"
        case .networkDownloadRate: return "DN"
        case .networkUploadRate:   return "UP"
        }
    }

    /// SF Symbol leading the chip and the menu bar segment. Temperatures use the thermometer rather
    /// than the component glyph: in the menu bar "cpu 42%" and "cpu 58°" would otherwise differ only
    /// by a degree sign.
    package var symbolName: String {
        switch self {
        case .cpuUsage:         return "cpu"
        case .gpuUsage:         return "cpu.fill"
        case .memoryUsage:      return "memorychip"
        case .cpuTemperature:   return "thermometer.medium"
        case .gpuTemperature:   return "thermometer.high"
        case .dieTemperature:   return "thermometer.medium"
        case .diskUsedPercentage, .diskFreeSpace:
            return "internaldrive"
        case .diskReadRate:
            return "arrow.down.circle"
        case .diskWriteRate:
            return "arrow.up.circle"
        case .networkDownloadRate:
            return "arrow.down"
        case .networkUploadRate:
            return "arrow.up"
        }
    }

    /// Why a reading may be missing, shown in Customize instead of leaving the row silently absent.
    package var unavailableNote: String {
        switch self {
        case .cpuUsage, .memoryUsage:
            return "Not readable on this Mac."
        case .gpuUsage:
            return "No GPU performance counters on this Mac."
        case .cpuTemperature, .gpuTemperature:
            return "This Mac doesn't label its thermal sensors per component."
        case .dieTemperature:
            return "No usable thermal sensors on this Mac."
        case .diskUsedPercentage, .diskFreeSpace, .diskReadRate, .diskWriteRate, .networkDownloadRate, .networkUploadRate:
            return "Not readable on this Mac."
        }
    }
}

package extension SystemMetricID.Kind {
    /// Whether `fraction` and `severity` describe a meaningful bounded range for this kind.
    var hasBoundedRange: Bool {
        switch self {
        case .percentage, .temperature:
            return true
        case .byteRate, .byteCount, .duration:
            return false
        }
    }
}

// MARK: - SystemMetric

/// One resolved reading. Mirrors `AgentUsageMetric`'s shape — a fraction for the meter and a
/// severity for the color — so the popover strip and the menu bar renderer treat system readings and
/// agent quotas the same way.
package struct SystemMetric: Identifiable, Hashable, Sendable {

    package let id: SystemMetricID

    /// The resolved value in the unit described by `id.kind`.
    let value: Double

    package init(id: SystemMetricID, value: Double) {
        self.id = id
        self.value = value
    }

    /// What goes next to the glyph: "42%" or "58°".
    package var displayText: String {
        switch id.kind {
        case .percentage:   return "\(Int(value.rounded()))%"
        case .temperature:  return "\(Int(value.rounded()))°"
        case .byteRate:
            return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) + "/s"
        case .byteCount:
            return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
        case .duration:
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = [.hour, .minute]
            return formatter.string(from: value) ?? ""
        }
    }

    /// 0…1 fill for the meter. Temperatures are mapped across the 30…100 °C band that a laptop
    /// actually moves through — anchoring the bar at 0 °C would leave it nearly static.
    package var fraction: Double {
        switch id.kind {
        case .percentage:
            return min(max(value / 100, 0), 1)
        case .temperature:
            return min(max((value - 30) / 70, 0), 1)
        case .byteRate, .byteCount, .duration:
            return 0
        }
    }

    package enum Severity {
        case normal, warning, critical
    }

    /// Load and heat need different bands: 90% CPU is normal under a build, 90 °C is not.
    package var severity: Severity {
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
        case .byteRate, .byteCount, .duration:
            return .normal
        }
    }

    /// Longer form for tooltips and accessibility ("CPU Usage: 42%").
    package var tooltip: String { "\(id.title): \(displayText)" }
}
