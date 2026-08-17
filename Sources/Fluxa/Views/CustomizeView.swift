import SwiftUI

// MARK: - CustomizeView

/// Sheet that lets the user reorder, show/hide actions, and toggle subtitle visibility.
/// All changes are written through to AppSettings immediately (with UserDefaults persistence).
struct CustomizeView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Customize")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Drag to reorder, switch to show or hide")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // CustomizeView lives in its own Window scene, so dismiss
                // closes just that window.
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

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
                    .tint(.blue)
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
                    .tint(.blue)
                } header: {
                    sectionHeader("SYSTEM")
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            // Note: editMode is iOS/tvOS only. On macOS, List with .onMove shows
            // drag handles automatically — no editMode needed.
        }
        .frame(width: 320, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        // Customize can be opened from the menu without the popover ever being shown, so make sure
        // the agent list has something to offer rather than explaining away an empty section.
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
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    (isSelected ? Color.blue.opacity(0.13) : Color.secondary.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("\(metric.providerName) · \(metric.label)")
                    .font(.system(size: 13))
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
            .tint(.blue)
            .disabled(isBlocked)
        }
        .padding(.vertical, 1)
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
    }

    private func hintRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
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
                .frame(width: 24, height: 24)
                .background(
                    (isHidden ? Color.secondary.opacity(0.08) : action.tint.opacity(0.13)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            Text(action.title)
                .font(.system(size: 13))
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
        .padding(.vertical, 1)
    }
}
