import SwiftUI
import FluxaCore

// MARK: - AgentUsageWindowView

/// Detail window for agent usage: the live quota reading for every window an agent exposes, plus a
/// GitHub-style contribution grid of the tokens spent each day.
///
/// The two halves come from different places on purpose. Quota percentages are live from each
/// agent's usage endpoint — accurate, but only ever "right now", with no history to ask for. The
/// grid instead is rebuilt from the agents' own session logs, which already hold weeks of exact
/// per-turn token counts, so the charts are populated the first time the window opens rather than
/// slowly filling from the moment the feature was switched on.
struct AgentUsageWindowView: View {

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var usage: AgentUsageService { viewModel.agentUsage }
    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        // The Window scene uses contentSize: expose both cards' full height, including any
        // additional quota rows, instead of trapping them in a shorter scroll viewport.
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .fluxaPanelSurface(classicBackground: Color(nsColor: .windowBackgroundColor))
        .onAppear {
            usage.refresh()
            usage.scanLogs()
        }
    }

    // MARK: - Header

    private var header: some View {
        FluxaPageHeader(
            title: "Agent Usage",
            subtitle: subtitle,
            systemImage: "chart.bar.xaxis",
            tint: FluxaTheme.accent
        ) {
            Button {
                usage.refresh(force: true)
                usage.scanLogs()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(FluxaButtonStyle())
            .disabled(usage.isRefreshing)
            .help("Refresh quotas and re-scan logs")
        }
    }

    private var subtitle: String {
        if usage.isScanningLogs { return "Reading session logs…" }
        if usage.isRefreshing { return "Refreshing…" }
        guard let last = usage.lastRefreshedAt else { return "Not read yet" }
        return "Updated \(last.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if usage.metrics.isEmpty && usage.dailyTokens.isEmpty {
            emptyState
        } else {
            VStack(spacing: 16) {
                ForEach(agents, id: \.self) { providerID in
                    agentCard(providerID)
                }
            }
            .padding(14)
        }
    }

    /// Agents that have either a live quota or logged history, in a stable order.
    private var agents: [String] {
        let fromMetrics = usage.metrics.map(\.providerID)
        let fromLogs = usage.dailyTokens.filter { !$0.value.isEmpty }.map(\.key)
        var seen: Set<String> = []
        return (fromMetrics + fromLogs.sorted()).filter { seen.insert($0).inserted }
    }

    private func agentCard(_ providerID: String) -> some View {
        let metrics = usage.metrics.filter { $0.providerID == providerID }
        let byDay = usage.dailyTokens[providerID] ?? [:]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentMarkView(providerID: providerID, size: 14)
                    .foregroundStyle(.secondary)
                Text(metrics.first?.providerName ?? providerID.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let total = totalTokens(byDay), total > 0 {
                    Text("\(ContributionGridView.compact(total)) tokens · 6 months")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // Live quota windows
            ForEach(metrics) { metric in
                quotaRow(metric)
            }

            if byDay.isEmpty {
                Text(usage.isScanningLogs
                     ? "Reading session logs…"
                     : "No session logs found for this agent.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                ContributionGridView(byDay: byDay, tint: tint(for: providerID))
            }
        }
        .padding(12)
        .background {
            if isCyber {
                FluxCutShape(cut: 10).fill(palette.module)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        }
        .overlay {
            if isCyber {
                FluxCutShape(cut: 10).stroke(palette.border, lineWidth: 1)
            }
        }
    }

    /// One live quota window: label, meter, percentage and reset countdown.
    private func quotaRow(_ metric: AgentUsageMetric) -> some View {
        HStack(spacing: 8) {
            Text(metric.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color(for: metric).gradient)
                        .frame(width: max(2, proxy.size.width * metric.fraction))
                }
            }
            .frame(height: 5)

            Text("\(metric.percentUsed)%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color(for: metric))
                .frame(width: 34, alignment: .trailing)

            Text(metric.resetNote() ?? "")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 96, alignment: .trailing)
        }
    }

    private func totalTokens(_ byDay: [Date: Int]) -> Int? {
        byDay.isEmpty ? nil : byDay.values.reduce(0, +)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No agent usage yet")
                .font(.system(size: 13, weight: .medium))
            Text(usage.agentErrors.values.sorted().first
                 ?? "Sign in with `claude` or `codex`, then refresh.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    // MARK: - Colors

    private func color(for metric: AgentUsageMetric) -> Color {
        if isCyber {
            return palette.agentColor(for: metric)
        }
        switch metric.severity {
        case .normal:   return .blue
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    /// One hue per agent so two grids in the same window stay distinguishable.
    private func tint(for providerID: String) -> Color {
        if isCyber {
            return palette.agentIdentity(for: providerID)
        }
        switch providerID {
        case "claude":      return .orange
        case "codex":       return .green
        case "antigravity": return .pink
        default:            return .blue
        }
    }
}
