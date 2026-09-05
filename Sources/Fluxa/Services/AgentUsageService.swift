import Foundation
import FluxaCore
import Observation

// MARK: - AgentUsageService

/// Collects AI coding agents' quota usage by reading each provider's own usage endpoint with the
/// credentials its CLI already stored on this Mac.
///
/// Claude's OAuth blob lives in the login keychain (`Claude Code-credentials`, or
/// `~/.claude/.credentials.json` where the CLI writes a file); Codex's lives in
/// `~/.codex/auth.json`; Antigravity's is a keychain item under service `gemini`. No agent's stored
/// credential is ever written back to — see `AgentCredentialStore` for why that stance is
/// deliberate, and `AntigravityUsageReader` for why deriving a token from Antigravity's refresh
/// credential doesn't breach it.
///
/// Each agent is fetched independently: one failing (or not being installed) leaves the others
/// showing their numbers, and the strip simply omits what it doesn't have.
@Observable
@MainActor
final class AgentUsageService {

    // MARK: - Observable State

    /// Latest metrics across all agents, ordered by agent then window.
    private(set) var metrics: [AgentUsageMetric] = []

    /// Per-agent failure text, keyed by agent name. Shown in Customize so a missing row is
    /// explained ("Claude: login expired…") instead of silently absent. Never surfaced as a popover
    /// error banner: a background usage read must not shout over the quick actions.
    private(set) var agentErrors: [String: String] = [:]

    /// True while a refresh is in flight, so the strip can dim slightly.
    private(set) var isRefreshing = false

    /// When the last successful pass completed.
    private(set) var lastRefreshedAt: Date?

    /// Daily token totals per agent, read from the agents' own session logs — the usage window's
    /// charts. Keyed providerID → local day → tokens.
    private(set) var dailyTokens: [String: [Date: Int]] = [:]

    /// True while the (potentially long) first log scan is running.
    private(set) var isScanningLogs = false

    private let logScanner = AgentLogScanner()
    private var scanTask: Task<Void, Never>?

    // MARK: - Tuning

    /// Floor on how often an *opportunistic* refresh (opening the popover) actually hits the
    /// network. Below three minutes a 5-hour window can't have moved a whole percentage point, so a
    /// shorter spacing would spend requests to redraw the same number.
    private static let minimumRefreshInterval: TimeInterval = 180

    /// How often the background loop wakes to check whether a refresh is due. Short so a change of
    /// interval in Customize takes effect promptly; the wake itself does no I/O.
    private static let tickInterval: Duration = .seconds(30)

    // MARK: - Private

    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - Public API

    /// Refreshes usage in the background. Cheap to call on every popover open: it returns
    /// immediately when the last read is still fresh, and coalesces concurrent calls.
    func refresh(force: Bool = false) {
        if !force, let lastRefreshedAt,
           Date().timeIntervalSince(lastRefreshedAt) < Self.minimumRefreshInterval {
            return
        }
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            await self?.performRefresh()
            self?.refreshTask = nil
        }
    }

    /// Starts the background refresh loop that keeps the menu bar current.
    ///
    /// Both closures are consulted on every tick rather than captured once: with no agent pinned the
    /// loop makes no request at all — and, just as importantly, never touches the keychain, so an
    /// install that doesn't use this feature is never prompted for Claude's credentials. Reading the
    /// interval per tick is what lets a change in Customize apply without a restart.
    func startAutoRefresh(
        isEnabled: @escaping @MainActor () -> Bool,
        interval: @escaping @MainActor () -> UsageRefreshInterval
    ) {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                if isEnabled(), let seconds = interval().seconds {
                    let elapsed = self?.lastRefreshedAt.map { Date().timeIntervalSince($0) }
                    if elapsed == nil || elapsed! >= seconds {
                        self?.refresh(force: true)
                    }
                }
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    /// Rebuilds the daily token history from the agents' session logs. Only the charts need it, so
    /// it runs when the usage window opens rather than on every quota refresh. Cheap after the first
    /// pass — unchanged log files are served from cache.
    func scanLogs() {
        guard scanTask == nil else { return }
        isScanningLogs = dailyTokens.isEmpty
        scanTask = Task { [weak self, logScanner] in
            let totals = await logScanner.scan()
            await MainActor.run {
                self?.applyScan(totals)
                self?.isScanningLogs = false
                self?.scanTask = nil
            }
        }
    }

    private func applyScan(_ totals: AgentLogScanner.DailyTotals) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        dailyTokens = totals.mapValues { byDay in
            var converted: [Date: Int] = [:]
            for (day, tokens) in byDay {
                guard let date = formatter.date(from: day) else { continue }
                converted[Calendar.current.startOfDay(for: date)] = tokens
            }
            return converted
        }
    }

    /// The metrics matching the user's selection, in the order they were selected — so the strip
    /// reads left-to-right the way the Customize list is arranged.
    func selectedMetrics(ids: [String]) -> [AgentUsageMetric] {
        ids.compactMap { id in metrics.first { $0.id == id } }
    }

    /// True when at least one agent's credentials were found — drives the Customize hint.
    var hasAnyAgent: Bool {
        !metrics.isEmpty || !agentErrors.isEmpty
    }

    // MARK: - Private

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // All agents in parallel: none depends on the others, and a slow endpoint shouldn't hold up
        // the ones that answered.
        async let claude = Self.read(agent: ClaudeUsageReader.agentName) { try await ClaudeUsageReader().fetch() }
        async let codex = Self.read(agent: CodexUsageReader.agentName) { try await CodexUsageReader().fetch() }
        async let antigravity = Self.read(agent: AntigravityUsageReader.agentName) { try await AntigravityUsageReader().fetch() }

        let results = await [claude, codex, antigravity]

        var collected: [AgentUsageMetric] = []
        var errors: [String: String] = [:]
        for result in results {
            collected.append(contentsOf: result.metrics)
            if let message = result.errorMessage {
                errors[result.agent] = message
            }
        }

        // Keep the previous values when a pass returned nothing at all: a transient network failure
        // shouldn't blank a strip that was showing good numbers a minute ago.
        if !collected.isEmpty || metrics.isEmpty {
            metrics = collected
        }
        agentErrors = errors
        if !collected.isEmpty {
            lastRefreshedAt = Date()
        }
    }

    private struct AgentResult {
        let agent: String
        let metrics: [AgentUsageMetric]
        let errorMessage: String?
    }

    /// Runs one agent's reader off the main actor and converts a throw into a per-agent message.
    private static func read(
        agent: String,
        _ fetch: @escaping () async throws -> [AgentUsageMetric]
    ) async -> AgentResult {
        do {
            return AgentResult(agent: agent, metrics: try await fetch(), errorMessage: nil)
        } catch {
            return AgentResult(agent: agent, metrics: [], errorMessage: error.localizedDescription)
        }
    }
}
