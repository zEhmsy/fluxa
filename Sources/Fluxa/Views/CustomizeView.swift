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
            FluxaPageHeader(
                title: "Customize Fluxa",
                subtitle: "Arrange actions and menu-bar metrics",
                systemImage: "slider.horizontal.3",
                tint: FluxaTheme.accent
            ) {
                Button("Done", action: onDone)
                    .buttonStyle(FluxaPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
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
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Appearance")
                            .font(.system(size: 13))

                        Picker("Appearance", selection: Binding(
                            get: { settings.visualStyle },
                            set: { settings.visualStyle = $0 }
                        )) {
                            ForEach(FluxaVisualStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .accessibilityLabel("Fluxa appearance")
                        .help("Classic follows macOS. Cyber and Cyber Dark use the Control Deck design.")
                    }
                    .padding(.vertical, 3)
                    .fluxaListRowSurface()

                    Toggle("Show Subtitles", isOn: Binding(
                        get: { settings.showSubtitles },
                        set: { settings.showSubtitles = $0 }
                    ))
                    .font(.system(size: 13))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(FluxaTheme.accent)
                    .fluxaListRowSurface()
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
                    .fluxaListRowSurface()
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
        .fluxaPanelSurface()
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

    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    private var isHidden: Bool {
        settings.hiddenActionIDs.contains(action.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHidden ? .secondary : action.tint)
                .frame(width: 28, height: 28)
                .fluxaModuleChrome(
                    fill: isHidden
                        ? (isCyber ? palette.recessed : FluxaTheme.elevatedSurface)
                        : action.tint.opacity(0.10),
                    border: isHidden
                        ? (isCyber ? palette.border : FluxaTheme.border)
                        : action.tint.opacity(isCyber ? 0.30 : 0.20),
                    cornerRadius: 7,
                    cut: 7
                )
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
        .fluxaListRowSurface()
    }
}
