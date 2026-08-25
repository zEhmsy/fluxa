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

                // MARK: System Stats
                Section {
                    CustomizeSystemStatsSection(settings: settings, stats: viewModel.systemStats)
                } header: {
                    sectionHeader("SYSTEM STATS")
                }

                // MARK: Agent Usage
                Section {
                    CustomizeAgentUsageSection(settings: settings, usage: viewModel.agentUsage)
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
        // Refresh on entry so both metric sections are populated even when nothing is pinned yet.
        .onAppear {
            viewModel.agentUsage.refresh()
            viewModel.systemStats.refreshNow()
        }
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
