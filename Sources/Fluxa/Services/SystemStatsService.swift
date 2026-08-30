import Foundation
import FluxaCore
import Observation

// MARK: - SystemStatsService

/// Publishes live CPU, GPU, memory and temperature readings for the popover strip and the menu bar.
///
/// Deliberately separate from `AgentUsageService`: that one makes network requests every few
/// minutes and can fail per agent, this one makes local syscalls every few seconds and can only be
/// unavailable. Sharing a service would have meant one refresh policy for two very different costs.
///
/// The sampling loop only runs while something is actually displaying a reading. With no metric
/// selected in Customize the timer never starts, so an install that doesn't use the feature pays
/// nothing — the same stance `AgentUsageService` takes toward the keychain.
@Observable
@MainActor
final class SystemStatsService {

    // MARK: - Observable State

    /// Latest readings in `SystemMetricID.allCases` order. Only metrics this Mac can actually
    /// report appear here.
    private(set) var metrics: [SystemMetric] = []

    /// True once a pass has completed, so the UI can tell "not sampled yet" from "unavailable".
    private(set) var hasSampled = false

    /// Rolling, in-memory samples for the detail dashboard. Nothing is written to disk: history
    /// begins when Fluxa launches and is capped to the most recent 30 minutes.
    private(set) var history: [SystemStatsHistorySample] = []

    /// Timestamp of the latest completed pass, including a pass where an individual source failed.
    private(set) var lastSampledAt: Date?

    static let historyDuration: TimeInterval = 30 * 60

    // MARK: - Private

    private let sampler = SystemStatsSampler()
    private var loopTask: Task<Void, Never>?

    /// Consulted on every tick rather than captured once, so changing the interval in Customize
    /// applies without a restart — and so turning every metric off stops the work immediately.
    private var isEnabled: @MainActor () -> Bool = { false }
    private var interval: @MainActor () -> SystemStatsInterval = { .fallback }
    private var isDashboardVisible = false

    // MARK: - Public API

    /// Starts the sampling loop. Safe to call more than once; only the first call takes effect.
    func start(
        isEnabled: @escaping @MainActor () -> Bool,
        interval: @escaping @MainActor () -> SystemStatsInterval
    ) {
        self.isEnabled = isEnabled
        self.interval = interval

        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Takes one reading now, regardless of the loop. Called when the popover opens so the strip
    /// isn't blank for up to a full interval.
    func refreshNow() {
        Task { [weak self] in
            guard let self else { return }
            let sample = await self.sampler.sample()
            self.apply(sample)
        }
    }

    /// Keeps sampling while the detail window is visible, even if the user removes every pinned
    /// strip/menu-bar metric while that window is open.
    func setDashboardVisible(_ isVisible: Bool) {
        isDashboardVisible = isVisible
        let minimumAge = max(0.5, interval().seconds / 2)
        let needsFreshSample = lastSampledAt.map { Date().timeIntervalSince($0) >= minimumAge } ?? true
        if isVisible && needsFreshSample {
            refreshNow()
        }
    }

    /// Clears only the chart history. Current readings stay intact and the next pass starts a new
    /// trace immediately.
    func clearHistory() {
        history.removeAll(keepingCapacity: true)
    }

    /// The selected readings, in the order the ids were given — so the strip reads left to right the
    /// way Customize is arranged. Ids with no current reading are skipped.
    func selectedMetrics(ids: [String]) -> [SystemMetric] {
        ids.compactMap { id in metrics.first { $0.id.rawValue == id } }
    }

    /// Whether this Mac reports the given metric at all. Drives Customize showing a row as
    /// unavailable instead of hiding it, so the absence is explained.
    func isAvailable(_ id: SystemMetricID) -> Bool {
        metrics.contains { $0.id == id }
    }

    // MARK: - Loop

    private func runLoop() async {
        // The CPU sampler needs a baseline before it can express a percentage; taking it here means
        // the very first published sample already carries a CPU number.
        await sampler.prime()

        while !Task.isCancelled {
            let shouldSample = isEnabled() || isDashboardVisible
            if shouldSample {
                let sample = await sampler.sample()
                apply(sample)
            }
            // Read per iteration so a change in Customize takes effect on the next tick. When
            // nothing is enabled this still sleeps, but the sleep is the only work being done.
            let seconds = shouldSample ? interval().seconds : SystemStatsInterval.fallback.seconds
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    /// Last good reading per metric, so a single failed pass doesn't blank a chip that was showing a
    /// number a moment ago — the same stance `AgentUsageService` takes toward a dropped request.
    /// A metric this Mac never reported at all is simply never added.
    private var lastKnown: [SystemMetricID: Double] = [:]

    private func apply(_ sample: SystemStatsSample) {
        let timestamp = Date()
        var collected: [SystemMetric] = []
        var measuredValues: [SystemMetricID: Double] = [:]

        // Built in `allCases` order so the set is stable between passes — a metric never reshuffles
        // its neighbours.
        for id in SystemMetricID.allCases {
            if let value = sample.value(for: id) {
                lastKnown[id] = value
                measuredValues[id] = value
            }
            guard let value = lastKnown[id] else { continue }
            collected.append(SystemMetric(id: id, value: value))
        }

        metrics = collected
        lastSampledAt = timestamp
        hasSampled = true

        guard !measuredValues.isEmpty else { return }

        history.append(SystemStatsHistorySample(timestamp: timestamp, values: measuredValues))
        let cutoff = timestamp.addingTimeInterval(-Self.historyDuration)
        if let firstRetained = history.firstIndex(where: { $0.timestamp >= cutoff }), firstRetained > 0 {
            history.removeFirst(firstRetained)
        }
    }
}
