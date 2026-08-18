import SwiftUI

// MARK: - CustomizeView

/// In-popover screen that lets the user reorder, show/hide actions, and toggle subtitle visibility.
/// All changes are written through to AppSettings immediately (with UserDefaults persistence).
struct CustomizeView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(PopoverViewModel.self) private var viewModel

    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(FluxaTheme.accent.opacity(0.12))
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FluxaTheme.accent)
                }
                .frame(width: 30, height: 30)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(FluxaTheme.accent.opacity(0.22), lineWidth: 1)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Customize Fluxa")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Arrange actions and menu-bar metrics")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done", action: onDone)
                    .buttonStyle(FluxaPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(FluxaTheme.surface)
            .overlay(alignment: .bottom) {
                FluxaPanelDivider(horizontalInset: 0)
            }

            // MARK: Action List (reorderable + togglable)
            List {
                Section {
                    ForEach(settings.actionOrder, id: \.self) { id in
                        if let action = ActionCatalog.action(for: id) {
                            CustomizeRowView(action: action, settings: settings)
                        }
                    }
                    .onMove { from, to in
                        settings.actionOrder.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    sectionHeader("ACTIONS")
                }

                // MARK: Agent Usage
                Section {
                    agentUsageRows
                } header: {
                    sectionHeader("AGENT USAGE")
                }

                // MARK: Display Options
                Section {
                    Toggle("Show Subtitles", isOn: Binding(
                        get: { settings.showSubtitles },
                        set: { settings.showSubtitles = $0 }
                    ))
                    .font(.system(size: 13))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(FluxaTheme.accent)
                    .listRowBackground(FluxaTheme.surface)
                    .listRowSeparatorTint(FluxaTheme.border)
                } header: {
                    sectionHeader("DISPLAY")
                }

                // MARK: System
                Section {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { viewModel.launchAtLogin.isEnabled },
                        set: { enabled in
                            try? viewModel.launchAtLogin.setEnabled(enabled)
                        }
                    ))
                    .font(.system(size: 13))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(FluxaTheme.accent)
                    .listRowBackground(FluxaTheme.surface)
                    .listRowSeparatorTint(FluxaTheme.border)
                } header: {
                    sectionHeader("SYSTEM")
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .tint(FluxaTheme.accent)
            // Note: editMode is iOS/tvOS only. On macOS, List with .onMove shows
            // drag handles automatically — no editMode needed.
        }
        .frame(width: FluxaTheme.panelWidth, height: 500)
        .background(FluxaTheme.panelBackground)
        // Refresh on entry so the agent section is populated even when no metric is pinned yet.
        .onAppear { viewModel.agentUsage.refresh() }
    }

    // MARK: - Agent Usage Section

    /// Picks which agent quota windows appear in the popover's usage strip. The list is what the last
    /// refresh read from each agent's own usage endpoint, so it fills in a moment after this window
    /// opens. Per-agent failures are spelled out rather than leaving a row silently missing.
    @ViewBuilder
    private var agentUsageRows: some View {
        let usage = viewModel.agentUsage
        if usage.metrics.isEmpty && usage.agentErrors.isEmpty {
            hintRow(usage.isRefreshing
                ? "Reading agent quotas…"
                : "Sign in with `claude` or `codex` to show agent quotas here.")
        } else {
            ForEach(usage.metrics) { metric in
                agentUsageRow(metric)
            }
            refreshIntervalRow
            ForEach(usage.agentErrors.sorted(by: { $0.key < $1.key }), id: \.key) { _, message in
                hintRow(message)
            }
            if !usage.metrics.isEmpty {
                hintRow("Up to \(AppSettings.maxUsageMetrics) fit across the strip.")
            }
        }
    }

    private func agentUsageRow(_ metric: AgentUsageMetric) -> some View {
        let isSelected = settings.usageMetricIDs.contains(metric.id)
        // At capacity the unselected rows can't be added; dimming them explains why the switch
        // won't move instead of letting the tap fail silently.
        let isBlocked = !isSelected && settings.usageMetricIDs.count >= AppSettings.maxUsageMetrics

        return HStack(spacing: 10) {
            AgentMarkView(providerID: metric.providerID, size: 13)
                .foregroundStyle(isSelected ? FluxaTheme.accent : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    (isSelected ? FluxaTheme.accent.opacity(0.12) : FluxaTheme.elevatedSurface),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? FluxaTheme.accent.opacity(0.24) : FluxaTheme.border, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(metric.providerName) · \(metric.label)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isBlocked ? .secondary : .primary)
                Text("\(metric.percentUsed)% used")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { selected in
                    if selected {
                        guard settings.usageMetricIDs.count < AppSettings.maxUsageMetrics else { return }
                        settings.usageMetricIDs.append(metric.id)
                    } else {
                        settings.usageMetricIDs.removeAll { $0 == metric.id }
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(FluxaTheme.accent)
            .disabled(isBlocked)
        }
        .padding(.vertical, 2)
        .listRowBackground(FluxaTheme.surface)
        .listRowSeparatorTint(FluxaTheme.border)
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
        .listRowBackground(FluxaTheme.surface)
        .listRowSeparatorTint(FluxaTheme.border)
    }

    private func hintRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
            .listRowBackground(FluxaTheme.surface)
            .listRowSeparatorTint(FluxaTheme.border)
    }

    private func sectionHeader(_ title: String) -> some View {
        FluxaSectionLabel(title: title)
            .padding(.top, 4)
    }
}

// MARK: - CustomizeRowView

/// A single row in the Customize list with tinted icon tile, name, and visibility switch.
private struct CustomizeRowView: View {

    let action: QuickAction
    let settings: AppSettings

    private var isHidden: Bool {
        settings.hiddenActionIDs.contains(action.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHidden ? .secondary : action.tint)
                .frame(width: 28, height: 28)
                .background(
                    (isHidden ? FluxaTheme.elevatedSurface : action.tint.opacity(0.10)),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isHidden ? FluxaTheme.border : action.tint.opacity(0.20), lineWidth: 1)
                }
                .accessibilityHidden(true)

            Text(action.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHidden ? .secondary : .primary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { !isHidden },
                set: { visible in
                    if visible {
                        settings.hiddenActionIDs.remove(action.id)
                    } else {
                        settings.hiddenActionIDs.insert(action.id)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(action.tint)
        }
        .padding(.vertical, 2)
        .listRowBackground(FluxaTheme.surface)
        .listRowSeparatorTint(FluxaTheme.border)
    }
}
