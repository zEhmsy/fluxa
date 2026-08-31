import SwiftUI

// MARK: - CustomizeView

/// In-popover settings grouped into compact tabs, without one long scrolling preferences list.
/// App preferences use AppSettings; update preferences are owned and persisted by Sparkle.
struct CustomizeView: View {

    static let panelWidth: CGFloat = 480
    private static let actionRowHeight: CGFloat = 32

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case actions = "Actions"
        case system = "System"
        case agents = "Agents"
        case updates = "Updates"

        var id: Self { self }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(PopoverViewModel.self) private var viewModel

    @State private var selectedTab: SettingsTab = .general

    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FluxaPageHeader(
                title: "Customize Fluxa",
                subtitle: "Appearance, actions and live readings",
                systemImage: "slider.horizontal.3",
                tint: FluxaTheme.accent
            ) {
                Button("Done", action: onDone)
                    .buttonStyle(FluxaPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }

            VStack(spacing: 12) {
                Picker("Settings section", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Settings section")

                tabContent
                    .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
            }
            .padding(12)
        }
        .frame(width: Self.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .fluxaPanelSurface()
        // Refresh once on entry, not whenever the user changes tabs.
        .onAppear {
            viewModel.agentUsage.refresh()
            viewModel.systemStats.refreshNow()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalTab
        case .actions:
            actionsTab
        case .system:
            systemTab
        case .agents:
            agentsTab
        case .updates:
            updatesTab
        }
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("DISPLAY")
            FluxaToolCard {
                VStack(alignment: .leading, spacing: 12) {
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

                    Toggle("Show Subtitles", isOn: Binding(
                        get: { settings.showSubtitles },
                        set: { settings.showSubtitles = $0 }
                    ))
                    .font(.system(size: 13))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(FluxaTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            sectionHeader("STARTUP")
            FluxaToolCard {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            sectionHeader("SETUP")
            FluxaToolCard {
                Button {
                    viewModel.isShowingPermissionsSetup = true
                } label: {
                    HStack {
                        Label("Permissions & First Run", systemImage: "checkmark.shield")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .multilineTextAlignment(.leading)
    }

    // MARK: - Actions

    private var actionsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ACTIONS")
            Text("Drag to reorder. Turn off an action to hide it from the dashboard.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Keep native List reordering, but reserve space for every row instead of scrolling.
            List {
                ForEach(settings.actionOrder, id: \.self) { id in
                    if let action = ActionCatalog.action(for: id) {
                        CustomizeRowView(action: action, settings: settings)
                            .frame(height: Self.actionRowHeight)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .listRowSeparator(.hidden)
                    }
                }
                .onMove(perform: moveActions)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, Self.actionRowHeight)
            .scrollContentBackground(.hidden)
            .contentMargins(0, for: .scrollContent)
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            // Leave room for native macOS row spacing and the list's edge insets as well.
            .frame(height: CGFloat(settings.actionOrder.count) * (Self.actionRowHeight + 4) + 8)
            .tint(FluxaTheme.accent)
        }
    }

    private func moveActions(fromOffsets source: IndexSet, toOffset destination: Int) {
        settings.actionOrder.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Readings

    private var systemTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("SYSTEM STATS")
            visibilityLegend
            FluxaToolCard {
                VStack(spacing: 12) {
                    CustomizeSystemStatsSection(settings: settings, stats: viewModel.systemStats)
                }
            }

            sectionHeader("ALERTS")
            Text("Notify after a limit holds for 30 seconds. Alerts re-arm only after the reading clears the reset band.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FluxaToolCard {
                VStack(spacing: 12) {
                    CustomizeAlertThresholdsSection(
                        settings: settings,
                        permissions: viewModel.permissions
                    )
                }
            }
        }
    }

    private var agentsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("AGENT USAGE")
            visibilityLegend
            FluxaToolCard {
                VStack(spacing: 12) {
                    CustomizeAgentUsageSection(settings: settings, usage: viewModel.agentUsage)
                }
            }
        }
    }

    private var visibilityLegend: some View {
        HStack(spacing: 14) {
            Text("Show readings in:")
            Label("Popover", systemImage: "rectangle.inset.filled")
            Label("Menu bar", systemImage: "menubar.rectangle")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    // MARK: - Updates

    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("UPDATES")
            FluxaToolCard {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Automatically Check for Updates", isOn: Binding(
                        get: { viewModel.updates.automaticallyChecksForUpdates },
                        set: { viewModel.updates.setAutomaticallyChecksForUpdates($0) }
                    ))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(FluxaTheme.accent)
                    .disabled(!viewModel.updates.isStarted)

                    Text(viewModel.updates.configurationError
                         ?? "Checks daily when enabled. You choose when to download and install.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FluxaToolCard {
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: viewModel.checkForUpdates) {
                        Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(FluxaButtonStyle())
                    .disabled(!viewModel.updates.canCheckForUpdates)

                    Text(viewModel.updates.statusDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .multilineTextAlignment(.leading)
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
            .accessibilityLabel("Show \(action.title)")
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(action.tint)
        }
        .padding(.vertical, 2)
        .fluxaListRowSurface()
    }
}
