import SwiftUI
import FluxaCore

// MARK: - System Metric Pulse

enum ControlDeckMetricRole: Equatable {
    case dominant
    case satellite
}

struct ControlDeckMetricPulse: View {
    let metric: SystemMetric
    let role: ControlDeckMetricRole
    let palette: ControlDeckPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { palette.metricColor(for: metric) }

    var body: some View {
        Group {
            switch role {
            case .dominant:
                dominantBody
            case .satellite:
                satelliteBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.module, in: FluxCutShape(cut: role == .dominant ? 15 : 9))
        .overlay {
            FluxCutShape(cut: role == .dominant ? 15 : 9)
                .stroke(borderColor, lineWidth: 1)
        }
        .help(metric.tooltip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.id.title)
        .accessibilityValue(accessibilityValue)
    }

    private var dominantBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: metric.id.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(metric.id.shortLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(palette.primaryText)

                Spacer()

                severityPill
            }

            Spacer(minLength: 3)

            Text(metric.displayText)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .tracking(-1)
                .foregroundStyle(tint)
                .contentTransition(.numericText())

            Spacer(minLength: 5)

            metricMeter(showsThresholds: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var satelliteBody: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: metric.id.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(metric.id.shortLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.45)
                    .foregroundStyle(palette.secondaryText)

                Spacer(minLength: 2)

                Text(metric.displayText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }

            metricMeter(showsThresholds: false)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var severityPill: some View {
        switch metric.severity {
        case .normal:
            EmptyView()
        case .warning:
            ControlDeckStatusPill(text: "High", tint: tint, marker: .warning)
        case .critical:
            ControlDeckStatusPill(text: "Critical", tint: tint, marker: .critical)
        }
    }

    @ViewBuilder
    private func metricMeter(showsThresholds: Bool) -> some View {
        if metric.id.kind.hasBoundedRange {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.meterTrack)
                    Rectangle()
                        .fill(tint)
                        .frame(width: max(1, proxy.size.width * metric.fraction))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: metric.fraction)

                    if showsThresholds {
                        threshold(at: 0.75, width: proxy.size.width)
                        threshold(at: 0.90, width: proxy.size.width)
                    }
                }
            }
            .frame(height: role == .dominant ? 5 : 3)
            .accessibilityHidden(true)
        }
    }

    private func threshold(at fraction: Double, width: CGFloat) -> some View {
        Rectangle()
            .fill(palette.tertiaryText)
            .frame(width: 1, height: 9)
            .offset(x: width * fraction, y: -2)
    }

    private var borderColor: Color {
        switch metric.severity {
        case .normal:             return palette.border
        case .warning, .critical: return tint.opacity(0.72)
        }
    }

    private var accessibilityValue: String {
        switch metric.severity {
        case .normal:   return metric.displayText
        case .warning:  return "\(metric.displayText), elevated"
        case .critical: return "\(metric.displayText), critical"
        }
    }
}

// MARK: - Agent Quota Pulse

struct ControlDeckAgentPulse: View {
    let metric: AgentUsageMetric
    let displayName: String
    let palette: ControlDeckPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { palette.agentColor(for: metric) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                AgentMarkView(providerID: metric.providerID, size: 11)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(displayName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Text("\(metric.percentUsed)%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 1.5) {
                ForEach(0..<10, id: \.self) { index in
                    Rectangle()
                        .fill(index < filledSegmentCount ? tint : palette.meterTrack)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: filledSegmentCount)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(palette.recessed, in: FluxCutShape(cut: 7))
        .overlay(alignment: .leading) {
            Rectangle().fill(tint).frame(width: 2)
        }
        .overlay { FluxCutShape(cut: 7).stroke(palette.border, lineWidth: 1) }
        .help(tooltip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.providerName) \(metric.label)")
        .accessibilityValue("\(metric.percentUsed) percent used")
    }

    private var filledSegmentCount: Int {
        guard metric.percentUsed > 0 else { return 0 }
        return min(10, max(1, Int(ceil(metric.fraction * 10))))
    }

    private var tooltip: String {
        var parts = ["\(metric.providerName) · \(metric.label): \(metric.percentUsed)% used"]
        if let note = metric.resetNote() { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}
