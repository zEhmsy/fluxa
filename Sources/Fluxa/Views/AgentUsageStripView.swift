import SwiftUI
import FluxaCore

// MARK: - AgentUsageStripView

/// A compact row of agent quota percentages pinned under the popover header, so the numbers are
/// readable the instant the popover opens — without scrolling past the action list.
///
/// Deliberately small: one 30pt row for up to `AppSettings.maxUsageMetrics` agents, shown only when
/// the user has selected something in Customize. With nothing selected (the default) the popover
/// keeps exactly the height it had before.
struct AgentUsageStripView: View {

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings

    /// Closes the popover before the detail window opens, so the window isn't hidden behind it.
    var closePopover: (() -> Void)?

    /// Whether the strip has anything to draw. Checked by the parent so the divider around it can be
    /// dropped too — an empty bordered strip would cost height for nothing.
    static func hasContent(viewModel: PopoverViewModel, settings: AppSettings) -> Bool {
        !viewModel.agentUsage.selectedMetrics(ids: settings.usageMetricIDs).isEmpty
    }

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FluxaSectionLabel(title: "Agent usage", trailing: "View details")

            // The whole strip opens the detail window — the chips are too small to be individual
            // targets, and every one of them leads to the same place.
            Button {
                viewModel.isShowingAgentUsage = true
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
            .help("Open usage charts")
            .accessibilityLabel("Agent usage")
            .accessibilityValue(accessibilityValue)
            .opacity(viewModel.agentUsage.isRefreshing ? 0.62 : 1)
            .animation(.easeOut(duration: 0.15), value: viewModel.agentUsage.isRefreshing)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var metrics: [AgentUsageMetric] {
        viewModel.agentUsage.selectedMetrics(ids: settings.usageMetricIDs)
    }

    /// One agent: name over the percentage, with a hairline meter under both. The window label
    /// ("Session" / "Weekly") only shows when the same agent contributes more than one chip —
    /// at this width the agent name is the thing worth spending characters on.
    private func chip(for metric: AgentUsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                AgentMarkView(providerID: metric.providerID, size: 11)
                    .foregroundStyle(color(for: metric.severity))

                if let initial = windowInitial(for: metric) {
                    Text(initial)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 2)

                Text("\(metric.percentUsed)%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: metric.severity))
            }

            meter(for: metric)
        }
        .frame(maxWidth: .infinity)
        .help(tooltip(for: metric))
    }

    private func meter(for metric: AgentUsageMetric) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(color(for: metric.severity).gradient)
                    .frame(width: max(1, proxy.size.width * metric.fraction))
                    .animation(.easeOut(duration: 0.2), value: metric.fraction)
            }
        }
        .frame(height: 4)
    }

    /// The agent's mark carries its identity, so the window is only spelled out when the same agent
    /// contributes more than one chip — two identical marks would otherwise be ambiguous.
    private func windowInitial(for metric: AgentUsageMetric) -> String? {
        let sameProvider = metrics.filter { $0.providerID == metric.providerID }
        guard sameProvider.count > 1, let initial = metric.label.first else { return nil }
        return String(initial).uppercased()
    }

    private func tooltip(for metric: AgentUsageMetric) -> String {
        var parts = ["\(metric.providerName) · \(metric.label): \(metric.percentUsed)% used"]
        if let note = metric.resetNote() { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private var accessibilityValue: String {
        metrics
            .map { "\($0.providerName) \($0.label) \($0.percentUsed) percent used" }
            .joined(separator: ", ")
    }

    private func color(for severity: AgentUsageMetric.Severity) -> Color {
        switch severity {
        case .normal:   return FluxaTheme.blue
        case .warning:  return FluxaTheme.orange
        case .critical: return FluxaTheme.red
        }
    }
}
