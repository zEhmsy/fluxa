import SwiftUI

// MARK: - SystemStatsStripView

/// A compact row of live system readings pinned directly under the popover header, above the agent
/// usage strip.
///
/// Structurally a sibling of `AgentUsageStripView` — same chip geometry, same meter, same severity
/// colors — so the two strips read as one stack rather than two unrelated widgets. The whole strip
/// opens the detail dashboard, matching the interaction already established by Agent Usage.
struct SystemStatsStripView: View {

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings

    /// Closes the popover before the detail window opens, so the window isn't hidden behind it.
    var closePopover: (() -> Void)?

    /// Whether the strip has anything to draw. Checked by the parent so an empty bordered strip
    /// never costs the popover height for nothing.
    static func hasContent(viewModel: PopoverViewModel, settings: AppSettings) -> Bool {
        !viewModel.systemStats.selectedMetrics(ids: settings.systemMetricIDs).isEmpty
    }

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FluxaSectionLabel(title: "System", trailing: "View details")

            Button {
                viewModel.isShowingSystemStats = true
                closePopover?()
            } label: {
                HStack(spacing: 10) {
                    ForEach(metrics) { metric in
                        chip(for: metric)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    isHovering ? FluxaTheme.hoverFill : FluxaTheme.surface,
                    in: RoundedRectangle(cornerRadius: FluxaTheme.panelCornerRadius, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: FluxaTheme.panelCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FluxaTheme.panelCornerRadius, style: .continuous)
                        .stroke(isHovering ? FluxaTheme.accent.opacity(0.38) : FluxaTheme.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
            }
            .help("Open system dashboard")
            .accessibilityLabel("System stats")
            .accessibilityValue(accessibilityValue)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var metrics: [SystemMetric] {
        viewModel.systemStats.selectedMetrics(ids: settings.systemMetricIDs)
    }

    /// One reading: glyph and short name over the value, with a hairline meter under both.
    private func chip(for metric: SystemMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: metric.id.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color(for: metric.severity))

                Text(metric.id.shortLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 2)

                Text(metric.displayText)
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: metric.severity))
                    // The value changes every tick; without this the whole chip would animate.
                    .contentTransition(.numericText())
            }

            meter(for: metric)
        }
        .frame(maxWidth: .infinity)
        .help(metric.tooltip)
    }

    private func meter(for metric: SystemMetric) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(color(for: metric.severity).gradient)
                    .frame(width: max(1, proxy.size.width * metric.fraction))
                    .animation(.easeOut(duration: 0.25), value: metric.fraction)
            }
        }
        .frame(height: 4)
    }

    private var accessibilityValue: String {
        metrics
            .map { "\($0.id.title) \($0.displayText)" }
            .joined(separator: ", ")
    }

    private func color(for severity: SystemMetric.Severity) -> Color {
        switch severity {
        case .normal:   return FluxaTheme.teal
        case .warning:  return FluxaTheme.orange
        case .critical: return FluxaTheme.red
        }
    }
}
