import SwiftUI

// MARK: - CustomizeSystemStatsSection

/// The Customize rows that pick which system readings appear, and where.
///
/// Load and memory always get a row: they are readable on every Mac, and on the rare one where a
/// counter is missing the row says so rather than vanishing unexplained.
///
/// Temperatures are different. Which of them exists is a property of the machine — some Macs label
/// their thermal sensors per component and can separate CPU from GPU, others publish only unlabelled
/// die sensors and can offer a single reading. Listing all three and greying out two would present
/// the hardware's limitation as a fault; only the applicable ones are shown, and a Mac with no
/// usable sensors at all gets one line saying that.
struct CustomizeSystemStatsSection: View {

    let settings: AppSettings
    let stats: SystemStatsService

    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    var body: some View {
        ForEach(loadMetrics) { id in
            row(for: id)
        }
        ForEach(availableTemperatures) { id in
            row(for: id)
        }
        if stats.hasSampled && availableTemperatures.isEmpty {
            hintRow("No readable thermal sensors on this Mac.")
        }
        intervalRow
    }

    /// The readings every Mac is expected to have.
    private var loadMetrics: [SystemMetricID] {
        SystemMetricID.allCases.filter { !SystemMetricID.temperatures.contains($0) }
    }

    /// The temperature readings this particular Mac actually publishes. Before the first sample
    /// lands nothing is known, so none are offered rather than guessing.
    private var availableTemperatures: [SystemMetricID] {
        SystemMetricID.temperatures.filter { stats.isAvailable($0) }
    }

    // MARK: - Rows

    private func row(for id: SystemMetricID) -> some View {
        let metric = stats.metrics.first { $0.id == id }
        let isUnavailable = stats.hasSampled && metric == nil

        return HStack(spacing: 10) {
            Image(systemName: id.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isUnavailable ? Color.secondary : FluxaTheme.teal)
                .frame(width: 28, height: 28)
                .fluxaModuleChrome(
                    fill: isUnavailable
                        ? (isCyber ? palette.recessed : FluxaTheme.elevatedSurface)
                        : FluxaTheme.teal.opacity(0.10),
                    border: isUnavailable
                        ? (isCyber ? palette.border : FluxaTheme.border)
                        : FluxaTheme.teal.opacity(isCyber ? 0.30 : 0.20),
                    cornerRadius: 7,
                    cut: 7
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(id.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isUnavailable ? .secondary : .primary)
                Text(subtitle(for: id, metric: metric, isUnavailable: isUnavailable))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            MetricVisibilityToggles(
                inPopover: popoverBinding(for: id),
                inMenuBar: menuBarBinding(for: id),
                menuBarBlockedReason: menuBarBlockedReason,
                isUnavailable: isUnavailable
            )
        }
        .padding(.vertical, 2)
        .fluxaListRowSurface()
    }

    private func subtitle(for id: SystemMetricID, metric: SystemMetric?, isUnavailable: Bool) -> String {
        if let metric { return "\(metric.displayText) now" }
        return isUnavailable ? id.unavailableNote : "Reading…"
    }

    private func hintRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
            .fluxaListRowSurface()
    }

    /// Nil while there is room. Non-nil is both the reason and the signal to block the button.
    private var menuBarBlockedReason: String? {
        settings.menuBarMetricCount >= AppSettings.maxMenuBarMetrics
            ? "The menu bar already shows \(AppSettings.maxMenuBarMetrics) readings."
            : nil
    }

    /// How often the numbers are re-sampled, with the trade-off spelled out under the picker.
    private var intervalRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Sample")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.systemStatsInterval },
                    set: { settings.systemStatsInterval = $0 }
                )) {
                    ForEach(SystemStatsInterval.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Text(settings.systemStatsInterval.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .fluxaListRowSurface()
    }

    // MARK: - Bindings

    private func popoverBinding(for id: SystemMetricID) -> Binding<Bool> {
        Binding(
            get: { settings.systemMetricIDs.contains(id.rawValue) },
            set: { isOn in
                if isOn {
                    // The popover strip has its own, roomier cap — three chips across 328pt.
                    guard settings.systemMetricIDs.count < AppSettings.maxSystemMetrics else { return }
                    settings.systemMetricIDs.append(id.rawValue)
                } else {
                    settings.systemMetricIDs.removeAll { $0 == id.rawValue }
                }
            }
        )
    }

    private func menuBarBinding(for id: SystemMetricID) -> Binding<Bool> {
        Binding(
            get: { settings.systemMenuBarMetricIDs.contains(id.rawValue) },
            set: { isOn in
                if isOn {
                    guard settings.menuBarMetricCount < AppSettings.maxMenuBarMetrics else { return }
                    settings.systemMenuBarMetricIDs.append(id.rawValue)
                } else {
                    settings.systemMenuBarMetricIDs.removeAll { $0 == id.rawValue }
                }
            }
        )
    }
}
