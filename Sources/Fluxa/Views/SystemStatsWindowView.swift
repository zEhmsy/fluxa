import Charts
import FluxaCore
import SwiftUI

// MARK: - SystemStatsWindowView

/// In-memory history for the local system readings.
///
/// CPU, GPU and memory share a fixed 0…100 percent plot. Temperatures get their own chart and a
/// separate degree axis, because placing both units on one scale would make either load or heat
/// unreadable. The service continues using the user's normal sampling interval while this window is
/// visible; opening a chart never creates a second sampling loop.
struct SystemStatsWindowView: View {

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var stats: SystemStatsService { viewModel.systemStats }
    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                currentReadings
                HStack(alignment: .top, spacing: 14) {
                    percentagePanel
                    capacityPanel
                }
                HStack(alignment: .top, spacing: 14) {
                    temperaturePanel
                    networkPanel
                }
                PeripheralBatteryPanel(devices: viewModel.peripheralBattery.devices)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 700)
        .animation(.easeInOut(duration: 0.25), value: viewModel.peripheralBattery.devices)
        .fluxaPanelSurface()
        .onAppear {
            stats.setDashboardVisible(true)
            viewModel.peripheralBattery.refresh()
        }
        .onDisappear {
            stats.setDashboardVisible(false)
        }
    }

    // MARK: - Header

    private var header: some View {
        FluxaPageHeader(
            title: "System Dashboard",
            subtitle: headerSubtitle,
            systemImage: "waveform.path.ecg.rectangle",
            tint: FluxaTheme.teal
        ) {
            HStack(spacing: 8) {
                Button {
                    stats.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(FluxaButtonStyle())
                .disabled(stats.history.isEmpty)
                .help("Clear chart history")
                .accessibilityLabel("Clear chart history")

                Button {
                    stats.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(FluxaButtonStyle())
                .help("Sample now")
                .accessibilityLabel("Sample now")
            }
        }
    }

    private var headerSubtitle: String {
        let cadence = settings.systemStatsInterval.label
        guard let lastSampledAt = stats.lastSampledAt else {
            return "\(cadence) · starting in-memory history"
        }
        return "\(cadence) · updated \(lastSampledAt.formatted(date: .omitted, time: .standard))"
    }

    // MARK: - Current readings

    @ViewBuilder
    private var currentReadings: some View {
        if stats.metrics.isEmpty {
            FluxaToolCard {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(stats.hasSampled ? "No system readings are available." : "Reading system sensors…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        } else {
            let metrics = stats.metrics
            let midpoint = (metrics.count + 1) / 2
            let firstRow = metrics.prefix(midpoint)
            let secondRow = metrics.dropFirst(midpoint)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(firstRow) { metric in
                        SystemMetricCard(metric: metric, color: currentMetricColor(for: metric))
                    }
                }
                if !secondRow.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(secondRow) { metric in
                            SystemMetricCard(metric: metric, color: currentMetricColor(for: metric))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Percentage panel

    private var percentagePanel: some View {
        percentageChartCard(
            title: "Load & Memory",
            subtitle: "0–100% · rolling 30 minutes",
            ids: percentageMetricIDs,
            placeholder: "Collecting load history…",
            accessibilityLabel: "Load and memory history"
        )
    }

    private var capacityPanel: some View {
        percentageChartCard(
            title: "Capacity & Power",
            subtitle: capacitySubtitle,
            ids: capacityMetricIDs,
            placeholder: "Collecting capacity history…",
            accessibilityLabel: "Disk and battery capacity history"
        )
    }

    private var capacitySubtitle: String {
        guard let isOnACPower = stats.isOnACPower else {
            return "0–100% · rolling 30 minutes"
        }
        let source = isOnACPower ? "AC power" : "On battery"
        return "\(source) · 0–100% · 30 minutes"
    }

    private func percentageChartCard(
        title: String,
        subtitle: String,
        ids: [SystemMetricID],
        placeholder: String,
        accessibilityLabel: String
    ) -> some View {
        chartCard(title: title, subtitle: subtitle, ids: ids) {
            let points = historyPoints(for: ids)

            Chart(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Percent", point.value),
                    series: .value("Series", point.seriesID)
                )
                .foregroundStyle(seriesColor(for: point.metricID))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.linear)

                if stats.history.count < 2 {
                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Percent", point.value)
                    )
                    .foregroundStyle(seriesColor(for: point.metricID))
                    .symbolSize(22)
                }
            }
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: 0.0 ... 100.0)
            .chartXAxis { timeAxis }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, 25.0, 50.0, 75.0, 100.0]) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number))%")
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartOverlay { _ in
                if stats.history.count < 2 {
                    chartPlaceholder(placeholder)
                }
            }
            .accessibilityLabel(accessibilityLabel)
        }
    }

    // MARK: - Temperature panel

    @ViewBuilder
    private var temperaturePanel: some View {
        let ids = temperatureMetricIDs
        let points = historyPoints(for: ids)

        if ids.isEmpty && stats.hasSampled {
            FluxaToolCard {
                HStack(spacing: 10) {
                    Image(systemName: "thermometer.medium.slash")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Temperature")
                            .font(.system(size: 12, weight: .semibold))
                        Text("No readable thermal sensors on this Mac.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } else {
            chartCard(
                title: "Temperature",
                subtitle: "Degrees Celsius · rolling 30 minutes",
                ids: ids
            ) {
                Chart(points) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Temperature", point.value),
                        series: .value("Series", point.seriesID)
                    )
                    .foregroundStyle(seriesColor(for: point.metricID))
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)

                    if stats.history.count < 2 {
                        PointMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Temperature", point.value)
                        )
                        .foregroundStyle(seriesColor(for: point.metricID))
                        .symbolSize(22)
                    }
                }
                .chartXScale(domain: chartDomain)
                .chartYScale(domain: temperatureDomain(for: points))
                .chartXAxis { timeAxis }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text("\(Int(number))°")
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .chartOverlay { _ in
                    if stats.history.count < 2 {
                        chartPlaceholder("Collecting temperature history…")
                    }
                }
                .accessibilityLabel("Temperature history")
            }
        }
    }

    // MARK: - Network panel

    @ViewBuilder
    private var networkPanel: some View {
        let ids = networkMetricIDs
        let points = historyPoints(for: ids)

        chartCard(
            title: "Network Activity",
            subtitle: "Throughput · rolling 30 minutes",
            ids: ids
        ) {
            Chart(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Rate", point.value),
                    series: .value("Series", point.seriesID)
                )
                .foregroundStyle(seriesColor(for: point.metricID))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.linear)

                if stats.history.count < 2 {
                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Rate", point.value)
                    )
                    .foregroundStyle(seriesColor(for: point.metricID))
                    .symbolSize(22)
                }
            }
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: rateDomain(for: points))
            .chartXAxis { timeAxis }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(formatRate(number))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartOverlay { _ in
                if stats.history.count < 2 {
                    chartPlaceholder("Collecting network history…")
                }
            }
            .accessibilityLabel("Network activity history")
        }
    }

    // MARK: - Shared chart pieces

    private func chartCard<Content: View>(
        title: String,
        subtitle: String,
        ids: [SystemMetricID],
        @ViewBuilder content: () -> Content
    ) -> some View {
        FluxaToolCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                seriesLegend(ids)

                content()
                    .frame(height: 120)
            }
        }
    }

    private func seriesLegend(_ ids: [SystemMetricID]) -> some View {
        HStack(spacing: 14) {
            ForEach(ids) { id in
                HStack(spacing: 5) {
                    Circle()
                        .fill(seriesColor(for: id))
                        .frame(width: 6, height: 6)
                    Text(id.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 12)
        .accessibilityElement(children: .combine)
    }

    private var timeAxis: some AxisContent {
        AxisMarks(values: timeAxisValues) { value in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
            AxisTick().foregroundStyle(Color.primary.opacity(0.18))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date, format: .dateTime.hour().minute().second())
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    /// Keep labels away from the plot edges: centered labels placed exactly at the range end are
    /// otherwise clipped to an ellipsis by Swift Charts.
    private var timeAxisValues: [Date] {
        let domain = chartDomain
        let duration = domain.upperBound.timeIntervalSince(domain.lowerBound)
        return [0.2, 0.5, 0.8].map {
            domain.lowerBound.addingTimeInterval(duration * $0)
        }
    }

    private func chartPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }

    // MARK: - Data shaping

    private struct ChartPoint: Identifiable {
        struct ID: Hashable {
            let timestamp: Date
            let metricID: SystemMetricID
        }

        let timestamp: Date
        let metricID: SystemMetricID
        let value: Double
        let segment: Int

        var id: ID { ID(timestamp: timestamp, metricID: metricID) }
        var seriesID: String { "\(metricID.rawValue).\(segment)" }
    }

    private var percentageMetricIDs: [SystemMetricID] {
        [.cpuUsage, .gpuUsage, .memoryUsage].filter(hasData)
    }

    private var capacityMetricIDs: [SystemMetricID] {
        [.diskUsedPercentage, .batteryLevel].filter(hasData)
    }

    private var temperatureMetricIDs: [SystemMetricID] {
        SystemMetricID.temperatures.filter(hasData)
    }

    private var networkMetricIDs: [SystemMetricID] {
        [.networkDownloadRate, .networkUploadRate].filter(hasData)
    }

    private func hasData(for id: SystemMetricID) -> Bool {
        stats.metrics.contains { $0.id == id }
            || stats.history.contains { $0.value(for: id) != nil }
    }

    private func historyPoints(for ids: [SystemMetricID]) -> [ChartPoint] {
        var segmentByMetric: [SystemMetricID: Int] = [:]
        var points: [ChartPoint] = []

        for sample in stats.history {
            for id in ids {
                guard let value = sample.value(for: id) else {
                    segmentByMetric[id, default: 0] += 1
                    continue
                }
                points.append(ChartPoint(
                    timestamp: sample.timestamp,
                    metricID: id,
                    value: value,
                    segment: segmentByMetric[id, default: 0]
                ))
            }
        }
        return points
    }

    private var chartDomain: ClosedRange<Date> {
        let end = stats.lastSampledAt ?? Date()
        let rollingStart = end.addingTimeInterval(-SystemStatsService.historyDuration)
        let minimumVisibleStart = end.addingTimeInterval(-60)
        let oldestSample = stats.history.first?.timestamp ?? end
        let start = max(rollingStart, min(oldestSample, minimumVisibleStart))
        return start ... end
    }

    private func temperatureDomain(for points: [ChartPoint]) -> ClosedRange<Double> {
        guard let minimum = points.map(\.value).min(),
              let maximum = points.map(\.value).max() else {
            return 30 ... 100
        }

        var lower = floor((minimum - 3) / 5) * 5
        var upper = ceil((maximum + 3) / 5) * 5
        if upper - lower < 10 {
            lower -= 5
            upper += 5
        }
        return max(0, lower) ... min(125, upper)
    }

    private func rateDomain(for points: [ChartPoint]) -> ClosedRange<Double> {
        guard let maximum = points.map(\.value).max(), maximum > 0 else {
            return 0 ... 100_000
        }
        let upper = maximum * 1.15
        return 0 ... max(10_000, upper)
    }

    private func formatRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 B/s" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    // MARK: - Colors

    private func seriesColor(for id: SystemMetricID) -> Color {
        if isCyber {
            return palette.metricIdentity(for: id)
        }
        switch id {
        case .cpuUsage:        return FluxaTheme.blue
        case .gpuUsage:        return FluxaTheme.purple
        case .memoryUsage:     return FluxaTheme.orange
        case .cpuTemperature:  return FluxaTheme.cyan
        case .gpuTemperature:  return FluxaTheme.pink
        case .dieTemperature:  return FluxaTheme.teal
        case .batteryLevel, .batteryTimeRemaining:
            return FluxaTheme.green
        case .diskUsedPercentage, .diskFreeSpace:
            return FluxaTheme.blue
        case .diskReadRate:    return FluxaTheme.cyan
        case .diskWriteRate:   return FluxaTheme.orange
        case .networkDownloadRate: return FluxaTheme.blue
        case .networkUploadRate:   return FluxaTheme.purple
        }
    }

    /// Keep every element inside a live card visually coherent. Series identity wins in the normal
    /// state; warning and critical colors replace it as a unit when the reading crosses a threshold.
    private func currentMetricColor(for metric: SystemMetric) -> Color {
        if isCyber {
            return palette.metricColor(for: metric)
        }
        switch metric.severity {
        case .normal:   return seriesColor(for: metric.id)
        case .warning:  return FluxaTheme.orange
        case .critical: return FluxaTheme.red
        }
    }

}
