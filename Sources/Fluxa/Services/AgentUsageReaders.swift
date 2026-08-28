import Foundation

// MARK: - AgentUsageReadError

enum AgentUsageReadError: LocalizedError {
    case notLoggedIn(agent: String, hint: String)
    case tokenExpired(agent: String, hint: String)
    case missingScope(agent: String)
    case requestFailed(agent: String, status: Int)
    case invalidResponse(agent: String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn(let agent, let hint):
            return "\(agent): not logged in. \(hint)"
        case .tokenExpired(let agent, let hint):
            return "\(agent): login expired. \(hint)"
        case .missingScope(let agent):
            return "\(agent): this login can't read usage. Sign in again with the CLI."
        case .requestFailed(let agent, let status):
            return "\(agent): request failed (HTTP \(status))."
        case .invalidResponse(let agent):
            return "\(agent): unexpected response."
        }
    }
}

// MARK: - AgentHTTP

/// Minimal GET helper. Each agent's usage endpoint wants its own headers, so the caller supplies them.
private enum AgentHTTP {

    static func getJSON(
        url: URL,
        headers: [String: String],
        agent: String,
        timeout: TimeInterval = 10
    ) async throws -> (json: [String: Any], headers: [AnyHashable: Any]) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentUsageReadError.invalidResponse(agent: agent)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AgentUsageReadError.requestFailed(agent: agent, status: http.statusCode)
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AgentUsageReadError.invalidResponse(agent: agent)
        }
        return (json, http.allHeaderFields)
    }

    /// Reads a JSON number that may arrive as a number or a numeric string.
    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

// MARK: - ClaudeUsageReader

/// Reads Claude's quota windows from the same endpoint Claude Code itself uses:
/// `GET https://api.anthropic.com/api/oauth/usage`, authorized with the stored OAuth access token.
///
/// The response reports each window's `utilization` already as 0–100, so nothing is estimated here.
/// The `anthropic-beta` and `User-Agent` headers mirror the CLI — the endpoint is part of the OAuth
/// surface Claude Code talks to, not the public Messages API.
struct ClaudeUsageReader {
    static let agentName = "Claude"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let loginHint = "Run `claude` to sign in."

    func fetch() async throws -> [AgentUsageMetric] {
        guard let credentials = try AgentCredentialStore.loadClaude() else {
            throw AgentUsageReadError.notLoggedIn(agent: Self.agentName, hint: Self.loginHint)
        }
        guard credentials.canReadUsage else {
            throw AgentUsageReadError.missingScope(agent: Self.agentName)
        }
        // Deliberately not refreshed here — see AgentCredentialStore. Using the agent once renews it.
        guard !credentials.isExpired else {
            throw AgentUsageReadError.tokenExpired(agent: Self.agentName, hint: Self.loginHint)
        }

        let (json, _) = try await AgentHTTP.getJSON(
            url: Self.usageURL,
            headers: [
                "Authorization": "Bearer \(credentials.accessToken)",
                "Accept": "application/json",
                "Content-Type": "application/json",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-code/2.1.69",
            ],
            agent: Self.agentName
        )

        return [
            Self.window(json["five_hour"], id: "claude.session", label: "Session"),
            Self.window(json["seven_day"], id: "claude.weekly", label: "Weekly"),
            Self.window(json["seven_day_sonnet"], id: "claude.sonnet", label: "Sonnet"),
        ].compactMap { $0 }
    }

    /// One `{ utilization, resets_at }` window → a metric. Absent windows (a plan without that
    /// limit) simply produce nothing.
    private static func window(_ value: Any?, id: String, label: String) -> AgentUsageMetric? {
        guard let object = value as? [String: Any],
              let utilization = AgentHTTP.number(object["utilization"]),
              utilization.isFinite
        else { return nil }

        return AgentUsageMetric(
            id: id,
            providerID: "claude",
            providerName: agentName,
            label: label,
            percentUsed: min(100, max(0, Int(utilization.rounded()))),
            resetsAt: resetDate(object["resets_at"])
        )
    }

    /// `resets_at` is an ISO-8601 string on current builds, but older ones sent epoch seconds or
    /// milliseconds — both are accepted so a format change degrades to "no reset time", not no metric.
    private static func resetDate(_ value: Any?) -> Date? {
        if let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return AgentDate.parse(text)
        }
        guard let number = AgentHTTP.number(value), number.isFinite else { return nil }
        let seconds = abs(number) < 1e10 ? number : number / 1000
        return Date(timeIntervalSince1970: seconds)
    }
}

// MARK: - CodexUsageReader

/// Reads Codex's quota windows from `GET https://chatgpt.com/backend-api/wham/usage`, authorized
/// with the token the Codex CLI stores in `~/.codex/auth.json`.
///
/// Codex reports two windows under `rate_limit`: `primary_window` (normally the 5-hour session) and
/// `secondary_window` (weekly). It can move a sole weekly limit into the primary slot, so each
/// window is classified by its own `limit_window_seconds` when present, and only falls back to the
/// slot's usual meaning when that field is missing.
struct CodexUsageReader {
    static let agentName = "Codex"
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let loginHint = "Run `codex` to sign in."
    private static let sessionWindowSeconds: Double = 5 * 60 * 60
    private static let weeklyWindowSeconds: Double = 7 * 24 * 60 * 60

    func fetch() async throws -> [AgentUsageMetric] {
        guard let credentials = AgentCredentialStore.loadCodex() else {
            throw AgentUsageReadError.notLoggedIn(agent: Self.agentName, hint: Self.loginHint)
        }

        var headers = [
            "Authorization": "Bearer \(credentials.accessToken)",
            "Accept": "application/json",
            "User-Agent": "Fluxa",
        ]
        if let accountID = credentials.accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-Id"] = accountID
        }

        let (json, responseHeaders) = try await AgentHTTP.getJSON(
            url: Self.usageURL,
            headers: headers,
            agent: Self.agentName
        )

        let rateLimit = json["rate_limit"] as? [String: Any]
        // Codex echoes both percentages in response headers too; they cover the case where a window
        // object is present but omits `used_percent`.
        let primaryHeader = AgentHTTP.number(header(responseHeaders, "x-codex-primary-used-percent"))
        let secondaryHeader = AgentHTTP.number(header(responseHeaders, "x-codex-secondary-used-percent"))

        let candidates = [
            Self.candidate(rateLimit?["primary_window"], headerPercent: primaryHeader, slot: .session),
            Self.candidate(rateLimit?["secondary_window"], headerPercent: secondaryHeader, slot: .weekly),
        ].compactMap { $0 }

        return [
            Self.metric(for: .session, id: "codex.session", label: "Session", from: candidates),
            Self.metric(for: .weekly, id: "codex.weekly", label: "Weekly", from: candidates),
        ].compactMap { $0 }
    }

    // MARK: - Window classification

    private enum Slot { case session, weekly }

    private struct Candidate {
        let window: [String: Any]
        let percentUsed: Double
        /// What this window is according to its own `limit_window_seconds`, or nil when unstated.
        let declaredSlot: Slot?
        /// What the slot it arrived in usually means.
        let fallbackSlot: Slot
    }

    private static func candidate(_ value: Any?, headerPercent: Double?, slot: Slot) -> Candidate? {
        let window = value as? [String: Any] ?? [:]
        guard let percent = AgentHTTP.number(window["used_percent"]) ?? headerPercent,
              percent.isFinite
        else { return nil }

        let declared: Slot? = AgentHTTP.number(window["limit_window_seconds"]).flatMap { seconds in
            switch seconds {
            case sessionWindowSeconds: return .session
            case weeklyWindowSeconds: return .weekly
            default: return nil
            }
        }
        return Candidate(window: window, percentUsed: percent, declaredSlot: declared, fallbackSlot: slot)
    }

    /// A window that declares its own period wins the slot; otherwise the one that arrived in the
    /// matching slot is used.
    private static func metric(for slot: Slot, id: String, label: String, from candidates: [Candidate]) -> AgentUsageMetric? {
        let declared = candidates.first { $0.declaredSlot == slot }
        let fallback = candidates.first { $0.declaredSlot == nil && $0.fallbackSlot == slot }
        guard let candidate = declared ?? fallback else { return nil }

        return AgentUsageMetric(
            id: id,
            providerID: "codex",
            providerName: agentName,
            label: label,
            percentUsed: min(100, max(0, Int(candidate.percentUsed.rounded()))),
            resetsAt: resetDate(candidate.window)
        )
    }

    private static func resetDate(_ window: [String: Any]) -> Date? {
        if let resetAt = AgentHTTP.number(window["reset_at"]) {
            return Date(timeIntervalSince1970: resetAt)
        }
        if let after = AgentHTTP.number(window["reset_after_seconds"]) {
            return Date().addingTimeInterval(after)
        }
        return nil
    }

    private func header(_ headers: [AnyHashable: Any], _ name: String) -> String? {
        headers.first { ($0.key as? String)?.lowercased() == name }?.value as? String
    }
}

// MARK: - AgentDate

/// ISO-8601 parsing shared by the readers: the agents' timestamps sometimes carry fractional
/// seconds and sometimes don't, and `ISO8601DateFormatter` only accepts the exact shape it's
/// configured for.
enum AgentDate {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ text: String) -> Date? {
        withFractional.date(from: text) ?? plain.date(from: text)
    }
}
