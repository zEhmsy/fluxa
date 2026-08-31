import FluxaCore
import SwiftUI

// MARK: - SystemMetricCard

/// One live system reading in the dashboard's adaptive grid.
struct SystemMetricCard: View {
    let metric: SystemMetric
    let color: Color

    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: metric.id.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(metric.id.shortLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(metric.displayText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if metric.id.kind.hasBoundedRange {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: max(2, proxy.size.width * metric.fraction))
                            .animation(.easeOut(duration: 0.22), value: metric.fraction)
                    }
                }
                .frame(height: 4)
            } else {
                Spacer().frame(height: 4)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .fluxaModuleChrome(
            fill: isCyber ? palette.module : FluxaTheme.surface,
            border: isCyber ? palette.border : FluxaTheme.border,
            cornerRadius: 10,
            cut: 7
        )
        .help(metric.tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.id.title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        switch metric.severity {
        case .normal:   return metric.displayText
        case .warning:  return "\(metric.displayText), elevated"
        case .critical: return "\(metric.displayText), critical"
        }
    }
}
