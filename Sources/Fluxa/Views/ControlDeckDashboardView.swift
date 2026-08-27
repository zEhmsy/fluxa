import SwiftUI

// MARK: - ControlDeckDashboardView

/// Optional main popover composition shared by Cyber and Cyber Dark.
/// Classic remains a separate subtree in `PopoverRootView`, so this view can evolve without
/// creating visual regressions in the default interface.
struct ControlDeckDashboardView: View {
    let style: FluxaVisualStyle
    let onCustomize: () -> Void
    let onAbout: () -> Void
    var closePopover: (() -> Void)?

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var systemPulse = false
    @State private var agentPulse = false
    @State private var systemPulseTask: Task<Void, Never>?
    @State private var agentPulseTask: Task<Void, Never>?
    @State private var isSystemHovering = false
    @State private var isAgentHovering = false

    private static let headerIcon: NSImage? = {
        guard let url = Bundle.fluxaResources.url(forResource: "menu-icon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()

    private var palette: ControlDeckPalette { .resolve(style) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !systemMetrics.isEmpty {
                systemSection
            }

            if !agentMetrics.isEmpty {
                agentSection
            }

            if let errorMessage = viewModel.errorMessage {
                errorRow(errorMessage)
            }

            actionSection
            footer
        }
        .frame(width: FluxaTheme.panelWidth)
        .foregroundStyle(palette.primaryText)
        .background(palette.deck)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .onChange(of: viewModel.systemStats.lastSampledAt) { _, _ in
            pulseSystemRail()
        }
        .onChange(of: viewModel.agentUsage.lastRefreshedAt) { _, _ in
            pulseAgentRail()
        }
        .onDisappear {
            systemPulseTask?.cancel()
            agentPulseTask?.cancel()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            ZStack {
                ControlDeckRailCell(palette: palette)

                FluxCutShape(cut: 8)
                    .fill(palette.brandGradient)
                    .frame(width: 24, height: 24)
                    .overlay {
                        if let image = Self.headerIcon {
                            Image(nsImage: image)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.white)
                                .frame(width: 15, height: 15)
                        } else {
                            Image(systemName: "togglepower")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .frame(width: 40)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Fluxa")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("System controls")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                HStack(spacing: 5) {
                    Rectangle()
                        .fill(palette.cpu)
                        .frame(width: 5, height: 5)
                        .rotationEffect(.degrees(45))

                    Text("\(Int(settings.systemStatsInterval.seconds))s")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.35)
                        .foregroundStyle(palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("System sampling every \(Int(settings.systemStatsInterval.seconds)) seconds")
            }
            .padding(.leading, 2)
            .padding(.trailing, 12)
        }
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    // MARK: System

    private var systemSection: some View {
        VStack(spacing: 0) {
            ControlDeckSectionHeader(
                title: "System",
                trailing: "Live",
                nodeColor: systemRailColor,
                palette: palette
            )

            Button {
                viewModel.isShowingSystemStats = true
                closePopover?()
            } label: {
                HStack(spacing: 0) {
                    ControlDeckRailCell(
                        palette: palette,
                        segmentColor: systemRailColor,
                        showsBranch: true,
                        isPulsing: systemPulse
                    )

                    HStack(spacing: 8) {
                        if let dominantMetric {
                            ControlDeckMetricPulse(metric: dominantMetric, role: .dominant, palette: palette)
                                .frame(maxWidth: .infinity)
                                .frame(height: 88)
                        }

                        if !satelliteMetrics.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(satelliteMetrics) { metric in
                                    ControlDeckMetricPulse(metric: metric, role: .satellite, palette: palette)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 88)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .opacity(isSystemHovering ? 0.88 : 1)
                }
            }
            .buttonStyle(.plain)
            .onHover { isSystemHovering = $0 }
            .help("Open system dashboard")
            .accessibilityLabel("Open system dashboard")
        }
    }

    // MARK: Agents

    private var agentSection: some View {
        VStack(spacing: 0) {
            ControlDeckSectionHeader(
                title: "Agent usage",
                trailing: "View details",
                nodeColor: agentRailColor,
                palette: palette,
                trailingColor: agentRailColor
            )

            Button {
                viewModel.isShowingAgentUsage = true
                closePopover?()
            } label: {
                HStack(spacing: 0) {
                    ControlDeckRailCell(
                        palette: palette,
                        segmentColor: agentRailColor,
                        showsBranch: true,
                        isPulsing: agentPulse
                    )

                    HStack(spacing: 8) {
                        ForEach(agentMetrics) { metric in
                            ControlDeckAgentPulse(
                                metric: metric,
                                displayName: agentDisplayName(for: metric),
                                palette: palette
                            )
                        }
                    }
                    .padding(.top, 2)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .opacity(isAgentHovering || viewModel.agentUsage.isRefreshing ? 0.74 : 1)
                }
            }
            .buttonStyle(.plain)
            .onHover { isAgentHovering = $0 }
            .help("Open usage charts")
            .accessibilityLabel("Open agent usage details")
        }
    }

    // MARK: Actions

    private var actionSection: some View {
        VStack(spacing: 0) {
            ControlDeckSectionHeader(
                title: "Quick actions",
                trailing: "\(visibleActions.count)",
                nodeColor: palette.tertiaryText,
                palette: palette
            )

            if visibleActions.count > 8 {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        actionRows
                    }
                }
                .scrollIndicators(.visible)
                .frame(height: 8 * 40)
            } else if visibleActions.isEmpty {
                emptyActions
            } else {
                VStack(spacing: 0) {
                    actionRows
                }
            }
        }
    }

    @ViewBuilder
    private var actionRows: some View {
        ForEach(visibleActions) { action in
            ControlDeckActionView(action: action, palette: palette, closePopover: closePopover)
        }
    }

    private var emptyActions: some View {
        HStack(spacing: 0) {
            ControlDeckRailCell(palette: palette)
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(palette.claude)
                Text("No visible actions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 44)
    }

    // MARK: Error and footer

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 0) {
            ControlDeckRailCell(
                palette: palette,
                node: .hollow(palette.critical),
                segmentColor: palette.critical,
                showsBranch: true
            )

            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.critical)
                    .accessibilityHidden(true)

                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)

                Spacer(minLength: 4)

                Button {
                    viewModel.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.critical)
                .accessibilityLabel("Dismiss error")
            }
            .padding(.horizontal, 8)
            .background(palette.critical.opacity(palette.isDark ? 0.10 : 0.06))
        }
        .frame(minHeight: 38)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            ControlDeckRailCell(palette: palette, node: .terminal)

            HStack(spacing: 9) {
                Button(action: onCustomize) {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(ControlDeckCutButtonStyle(
                    tint: palette.claude,
                    palette: palette,
                    reduceMotion: reduceMotion
                ))

                Button(action: onAbout) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText)
                .help("About Fluxa")
                .accessibilityLabel("About Fluxa")

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText)
            }
            .padding(.trailing, 12)
        }
        .frame(height: 42)
        .background(palette.recessed)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    // MARK: Data shaping

    private var visibleActions: [QuickAction] { settings.visibleActions }

    private var systemMetrics: [SystemMetric] {
        viewModel.systemStats.selectedMetrics(ids: settings.systemMetricIDs)
    }

    private var orderedSystemMetrics: [SystemMetric] {
        systemMetrics.enumerated()
            .sorted { left, right in
                let leftRank = severityRank(left.element.severity)
                let rightRank = severityRank(right.element.severity)
                return leftRank == rightRank ? left.offset < right.offset : leftRank > rightRank
            }
            .map(\.element)
    }

    private var dominantMetric: SystemMetric? { orderedSystemMetrics.first }
    private var satelliteMetrics: [SystemMetric] { Array(orderedSystemMetrics.dropFirst().prefix(2)) }

    private var systemRailColor: Color {
        dominantMetric.map(palette.metricColor(for:)) ?? palette.cpu
    }

    private var agentMetrics: [AgentUsageMetric] {
        viewModel.agentUsage.selectedMetrics(ids: settings.usageMetricIDs)
    }

    private var agentRailColor: Color {
        guard let leading = agentMetrics.enumerated().max(by: { left, right in
            let leftRank = severityRank(left.element.severity)
            let rightRank = severityRank(right.element.severity)
            return leftRank == rightRank ? left.offset > right.offset : leftRank < rightRank
        })?.element else {
            return palette.claude
        }
        return palette.agentColor(for: leading)
    }

    private func agentDisplayName(for metric: AgentUsageMetric) -> String {
        let sameProviderCount = agentMetrics.lazy.filter { $0.providerID == metric.providerID }.count
        guard sameProviderCount > 1 else { return metric.providerName }
        return "\(metric.providerName) \(metric.label.prefix(1).uppercased())"
    }

    private func severityRank(_ severity: SystemMetric.Severity) -> Int {
        switch severity {
        case .normal:   return 0
        case .warning:  return 1
        case .critical: return 2
        }
    }

    private func severityRank(_ severity: AgentUsageMetric.Severity) -> Int {
        switch severity {
        case .normal:   return 0
        case .warning:  return 1
        case .critical: return 2
        }
    }

    // MARK: Rail pulse

    private func pulseSystemRail() {
        systemPulseTask?.cancel()
        systemPulse = true
        guard !reduceMotion else {
            systemPulse = false
            return
        }
        systemPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            systemPulse = false
        }
    }

    private func pulseAgentRail() {
        agentPulseTask?.cancel()
        agentPulse = true
        guard !reduceMotion else {
            agentPulse = false
            return
        }
        agentPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            agentPulse = false
        }
    }
}
