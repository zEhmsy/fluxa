import Charts
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

    private var stats: SystemStatsService { viewModel.systemStats }

    var body: some View {
        VStack(spacing: 0) {
            header
            FluxaPanelDivider(horizontalInset: 0)

            VStack(spacing: 14) {
                currentReadings
                percentagePanel
                temperaturePanel
            }
            .padding(14)
        }
        .frame(width: 640, height: 620)
        .background(FluxaTheme.panelBackground)
        .onAppear {
            stats.setDashboardVisible(true)
        }
        .onDisappear {
            stats.setDashboardVisible(false)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FluxaTheme.teal)
                .frame(width: 36, height: 36)
                .background(
                    FluxaTheme.teal.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(FluxaTheme.teal.opacity(0.24), lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("System Dashboard")
                    .font(.system(size: 15, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            HStack(spacing: 9) {
                ForEach(stats.metrics) { metric in
                    metricCard(metric)
                }
            }
        }
    }

    private func metricCard(_ metric: SystemMetric) -> some View {
        let color = currentMetricColor(for: metric)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: metric.id.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(metric.id.shortLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(metric.displayText)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(2, proxy.size.width * metric.fraction))
                        .animation(.easeOut(duration: 0.22), value: metric.fraction)
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 79, alignment: .leading)
        .background(FluxaTheme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(FluxaTheme.border, lineWidth: 1)
        }
        .help(metric.tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.id.title)
        .accessibilityValue(metricAccessibilityValue(metric))
    }

    // MARK: - Percentage panel

    private var percentagePanel: some View {
        chartCard(
            title: "Load & Memory",
            subtitle: "0–100% · rolling 30 minutes",
            ids: percentageMetricIDs
        ) {
            let points = historyPoints(for: percentageMetricIDs)

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
                    chartPlaceholder("Collecting load history…")
                }
            }
            .accessibilityLabel("Load and memory history")
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
                    .frame(height: 136)
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

    private var temperatureMetricIDs: [SystemMetricID] {
        SystemMetricID.temperatures.filter(hasData)
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

    // MARK: - Colors

    private func seriesColor(for id: SystemMetricID) -> Color {
        switch id {
        case .cpuUsage:        return FluxaTheme.blue
        case .gpuUsage:        return FluxaTheme.purple
        case .memoryUsage:     return FluxaTheme.orange
        case .cpuTemperature:  return FluxaTheme.cyan
        case .gpuTemperature:  return FluxaTheme.pink
        case .dieTemperature:  return FluxaTheme.teal
        }
    }

    /// Keep every element inside a live card visually coherent. Series identity wins in the normal
    /// state; warning and critical colors replace it as a unit when the reading crosses a threshold.
    private func currentMetricColor(for metric: SystemMetric) -> Color {
        switch metric.severity {
        case .normal:   return seriesColor(for: metric.id)
        case .warning:  return FluxaTheme.orange
        case .critical: return FluxaTheme.red
        }
    }

    private func metricAccessibilityValue(_ metric: SystemMetric) -> String {
        switch metric.severity {
        case .normal:   return metric.displayText
        case .warning:  return "\(metric.displayText), elevated"
        case .critical: return "\(metric.displayText), critical"
        }
    }
}
