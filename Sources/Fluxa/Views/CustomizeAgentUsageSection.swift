import SwiftUI

// MARK: - CustomizeAgentUsageSection

/// The Customize rows that pick which agent quota windows appear, and where.
///
/// The list is what the last refresh read from each agent's own usage endpoint, so it fills in a
/// moment after Customize opens. Per-agent failures are spelled out rather than leaving a row
/// silently missing.
struct CustomizeAgentUsageSection: View {

    let settings: AppSettings
    let usage: AgentUsageService

    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    var body: some View {
        if usage.metrics.isEmpty && usage.agentErrors.isEmpty {
            hintRow(usage.isRefreshing
                ? "Reading agent quotas…"
                : "Sign in with `claude` or `codex` to show agent quotas here.")
        } else {
            ForEach(usage.metrics) { metric in
                row(for: metric)
            }
            refreshIntervalRow
            ForEach(usage.agentErrors.sorted(by: { $0.key < $1.key }), id: \.key) { _, message in
                hintRow(message)
            }
            if !usage.metrics.isEmpty {
                hintRow("Up to \(AppSettings.maxUsageMetrics) fit across the popover strip, "
                        + "\(AppSettings.maxMenuBarMetrics) across the menu bar.")
            }
        }
    }

    // MARK: - Rows

    private func row(for metric: AgentUsageMetric) -> some View {
        let isPinned = settings.usageMetricIDs.contains(metric.id)

        return HStack(spacing: 10) {
            AgentMarkView(providerID: metric.providerID, size: 13)
                .foregroundStyle(isPinned ? FluxaTheme.accent : Color.secondary)
                .frame(width: 28, height: 28)
                .fluxaModuleChrome(
                    fill: isPinned
                        ? FluxaTheme.accent.opacity(0.12)
                        : (isCyber ? palette.recessed : FluxaTheme.elevatedSurface),
                    border: isPinned
                        ? FluxaTheme.accent.opacity(isCyber ? 0.34 : 0.24)
                        : (isCyber ? palette.border : FluxaTheme.border),
                    cornerRadius: 7,
                    cut: 7
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("\(metric.providerName) · \(metric.label)")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(metric.percentUsed)% used")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            MetricVisibilityToggles(
                inPopover: popoverBinding(for: metric),
                inMenuBar: menuBarBinding(for: metric),
                menuBarBlockedReason: menuBarBlockedReason
            )
        }
        .padding(.vertical, 2)
        .fluxaListRowSurface()
    }

    /// How often the background read runs. The help text under it says what each choice buys, since
    /// "every 3 minutes" only means something once you know a session window moves 1% in that time.
    private var refreshIntervalRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Refresh")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.usageRefreshInterval },
                    set: { settings.usageRefreshInterval = $0 }
                )) {
                    ForEach(UsageRefreshInterval.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Text(settings.usageRefreshInterval.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .fluxaListRowSurface()
    }

    private func hintRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
            .fluxaListRowSurface()
    }

    // MARK: - Bindings

    private var menuBarBlockedReason: String? {
        settings.menuBarMetricCount >= AppSettings.maxMenuBarMetrics
            ? "The menu bar already shows \(AppSettings.maxMenuBarMetrics) readings."
            : nil
    }

    private func popoverBinding(for metric: AgentUsageMetric) -> Binding<Bool> {
        Binding(
            get: { settings.usageMetricIDs.contains(metric.id) },
            set: { isOn in
                if isOn {
                    guard settings.usageMetricIDs.count < AppSettings.maxUsageMetrics else { return }
                    settings.usageMetricIDs.append(metric.id)
                } else {
                    settings.usageMetricIDs.removeAll { $0 == metric.id }
                }
            }
        )
    }

    private func menuBarBinding(for metric: AgentUsageMetric) -> Binding<Bool> {
        Binding(
            get: { settings.usageMenuBarMetricIDs.contains(metric.id) },
            set: { isOn in
                if isOn {
                    guard settings.menuBarMetricCount < AppSettings.maxMenuBarMetrics else { return }
                    settings.usageMenuBarMetricIDs.append(metric.id)
                } else {
                    settings.usageMenuBarMetricIDs.removeAll { $0 == metric.id }
                }
            }
        )
    }
}
