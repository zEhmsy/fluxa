import SwiftUI
import FluxaCore

// MARK: - ControlDeckPalette

/// Fixed palette used by the optional Control Deck dashboards.
///
/// Unlike `FluxaTheme`, these colors do not follow the Mac's current appearance: choosing Cyber or
/// Cyber Dark is an explicit request for that exact presentation. Identity and severity resolution
/// live here so an icon, value, meter and rail segment can never drift to different colors.
struct ControlDeckPalette {
    let isDark: Bool

    let deck: Color
    let module: Color
    let recessed: Color
    let hover: Color
    let pressed: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let border: Color
    let meterTrack: Color

    let brandBlue: Color
    let brandViolet: Color
    let cpu: Color
    let gpu: Color
    let memory: Color
    let temperature: Color
    let battery: Color
    let claude: Color
    let codex: Color
    let antigravity: Color
    let warning: Color
    let critical: Color

    static func resolve(_ style: FluxaVisualStyle) -> ControlDeckPalette {
        style == .cyberDark ? .dark : .light
    }

    static let dark = ControlDeckPalette(
        isDark: true,
        deck: rgb(24, 25, 28),
        module: rgb(36, 37, 41),
        recessed: rgb(29, 30, 34),
        hover: rgb(43, 44, 49),
        pressed: rgb(50, 53, 60),
        primaryText: rgb(237, 238, 240),
        secondaryText: rgb(138, 141, 149),
        tertiaryText: rgb(110, 114, 122),
        border: rgb(61, 63, 70),
        meterTrack: rgb(49, 51, 58),
        brandBlue: rgb(47, 128, 237),
        brandViolet: rgb(108, 92, 231),
        cpu: rgb(84, 198, 235),
        gpu: rgb(190, 132, 255),
        memory: rgb(255, 167, 72),
        temperature: rgb(85, 211, 218),
        battery: rgb(89, 211, 133),
        claude: rgb(102, 174, 255),
        codex: rgb(84, 218, 166),
        antigravity: rgb(240, 142, 200),
        warning: rgb(255, 201, 82),
        critical: rgb(255, 112, 107)
    )

    static let light = ControlDeckPalette(
        isDark: false,
        deck: rgb(246, 247, 249),
        module: rgb(255, 255, 255),
        recessed: rgb(250, 251, 252),
        hover: rgb(236, 241, 248),
        pressed: rgb(224, 232, 243),
        primaryText: rgb(22, 24, 27),
        secondaryText: rgb(97, 102, 110),
        tertiaryText: rgb(124, 130, 139),
        border: rgb(216, 220, 227),
        meterTrack: rgb(231, 234, 239),
        brandBlue: rgb(47, 128, 237),
        brandViolet: rgb(108, 92, 231),
        cpu: rgb(0, 105, 143),
        gpu: rgb(112, 56, 176),
        memory: rgb(167, 70, 0),
        temperature: rgb(0, 112, 120),
        battery: rgb(20, 120, 68),
        claude: rgb(10, 91, 201),
        codex: rgb(19, 117, 83),
        antigravity: rgb(163, 42, 116),
        warning: rgb(132, 84, 0),
        critical: rgb(185, 48, 45)
    )

    var brandGradient: LinearGradient {
        LinearGradient(colors: [brandBlue, brandViolet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func metricIdentity(for id: SystemMetricID) -> Color {
        switch id {
        case .cpuUsage:        return cpu
        case .gpuUsage:        return gpu
        case .memoryUsage:     return memory
        case .cpuTemperature:  return cpu
        case .gpuTemperature:  return gpu
        case .dieTemperature:  return temperature
        case .batteryLevel, .batteryTimeRemaining:
            return battery
        case .diskUsedPercentage, .diskFreeSpace:
            return brandBlue
        case .diskReadRate:
            return cpu
        case .diskWriteRate:
            return memory
        case .networkDownloadRate:
            return brandBlue
        case .networkUploadRate:
            return brandViolet
        }
    }

    func metricColor(for metric: SystemMetric) -> Color {
        switch metric.severity {
        case .normal:   return metricIdentity(for: metric.id)
        case .warning:  return warning
        case .critical: return critical
        }
    }

    func agentIdentity(for providerID: String) -> Color {
        switch providerID {
        case "claude":      return claude
        case "codex":       return codex
        case "antigravity": return antigravity
        default:            return brandBlue
        }
    }

    func agentColor(for metric: AgentUsageMetric) -> Color {
        switch metric.severity {
        case .normal:   return agentIdentity(for: metric.providerID)
        case .warning:  return warning
        case .critical: return critical
        }
    }

    func actionColor(for id: ActionID) -> Color {
        switch id {
        case .keepAwake:      return isDark ? Self.rgb(255, 167, 72) : Self.rgb(167, 70, 0)
        case .darkMode:       return warning
        case .desktopIcons:   return temperature
        case .hiddenFiles:    return codex
        case .dockAutohide:   return isDark ? Self.rgb(205, 154, 118) : Self.rgb(116, 76, 50)
        case .screenSaver:    return gpu
        case .screenClean:    return cpu
        case .urlCleaner:     return brandBlue
        case .colorPicker:    return isDark ? Self.rgb(84, 218, 166) : Self.rgb(19, 117, 83)
        case .lockKeyboard:   return critical
        case .focusMode:      return isDark ? Self.rgb(150, 146, 255) : Self.rgb(69, 66, 155)
        case .audioOutput:    return claude
        case .bluetoothAudio: return cpu
        case .killProcess:    return critical
        case .micMute:        return isDark ? Self.rgb(255, 126, 192) : Self.rgb(171, 49, 115)
        case .lidAngle:       return isDark ? Self.rgb(89, 211, 133) : Self.rgb(20, 120, 68)
        case .trackpadScale:  return warning
        }
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }
}
