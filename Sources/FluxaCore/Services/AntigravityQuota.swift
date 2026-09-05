import Foundation

// MARK: - AntigravityQuota

/// The pure half of the Antigravity provider: turning what's already on disk and what the quota
/// endpoint answers into values the rest of the app understands.
///
/// Everything here is a pure function over `String`/`Data`, so the awkward parts — the credential
/// envelope, and the fact that the endpoint reports quota *remaining* while `AgentUsageMetric`
/// stores quota *used* — are testable without a Keychain or a network. The I/O lives in
/// `AntigravityUsageReader`.
package enum AntigravityQuota {

    // MARK: - Stored credential

    /// What Antigravity left in the Keychain for the signed-in account.
    ///
    /// The access token is short-lived and often already expired by the time Fluxa looks; the
    /// refresh token is what makes the provider usable at all. Either may be absent — a blob
    /// carrying only a bearer value still yields a usable read until it expires.
    package struct StoredCredential: Sendable, Equatable {
        package let accessToken: String?
        package let refreshToken: String?
        package let expiresAt: Date?

        package init(accessToken: String?, refreshToken: String?, expiresAt: Date?) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
        }

        /// Whether the access token is worth spending a request on. An unknown expiry is treated as
        /// usable: the endpoint's 401 is a cheaper way to find out than refusing to try.
        package func hasUsableAccessToken(now: Date = Date(), buffer: TimeInterval = 60) -> Bool {
            guard accessToken?.isEmpty == false else { return false }
            guard let expiresAt else { return true }
            return expiresAt.timeIntervalSince(now) > buffer
        }
    }

    /// Decodes the Keychain value written by the Antigravity app / `agy`.
    ///
    /// The value is JSON, usually behind a `go-keyring-base64:` wrapper, with the tokens either at
    /// the root or under a nested `token` object. Returns nil when the value is structured but
    /// unreadable — which is reported as "sign in again" rather than silently retried, since a blob
    /// we can't parse won't start parsing on the next tick.
    package static func credential(fromKeychainValue raw: String) -> StoredCredential? {
        guard let text = unwrapped(raw) else { return nil }

        // `.fragmentsAllowed` matters: without it a blob holding a bare JSON string is rejected as
        // JSON and falls through to the raw-value path, which would keep its surrounding quotes.
        if let json = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) {
            if let object = json as? [String: Any] {
                return credential(fromObject: object)
            }
            // A bare JSON string is the whole access token, with no refresh path.
            if let token = trimmed(json as? String) {
                return StoredCredential(accessToken: token, refreshToken: nil, expiresAt: nil)
            }
            return nil
        }

        // Structured material that failed to parse is damaged, not a bearer token. Sending it as one
        // would turn a clear "sign in again" into a confusing 401.
        if text.hasPrefix("{") || text.hasPrefix("[") { return nil }

        if text.hasPrefix(bearerPrefix), let token = trimmed(String(text.dropFirst(bearerPrefix.count))) {
            return StoredCredential(accessToken: token, refreshToken: nil, expiresAt: nil)
        }
        return trimmed(text).map { StoredCredential(accessToken: $0, refreshToken: nil, expiresAt: nil) }
    }

    private static let goKeyringPrefix = "go-keyring-base64:"
    private static let bearerPrefix = "Bearer "

    /// Strips the `go-keyring-base64:` wrapper when present. A value without it is already plain.
    private static func unwrapped(_ raw: String) -> String? {
        guard let text = trimmed(raw) else { return nil }
        guard text.hasPrefix(goKeyringPrefix) else { return text }

        let encoded = String(text.dropFirst(goKeyringPrefix.count))
        guard let data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]),
              let decoded = String(data: data, encoding: .utf8)
        else { return nil }
        return trimmed(decoded)
    }

    private static func credential(fromObject object: [String: Any]) -> StoredCredential? {
        // The documented shape nests the tokens under `token`; older/manual blobs put them at the
        // root. Anything else is not a credential we recognise.
        let source = (object["token"] as? [String: Any]) ?? object

        let access = firstString(source, ["access_token", "accessToken", "token", "id_token", "idToken"])
        let refresh = firstString(source, ["refresh_token", "refreshToken"])
        guard access != nil || refresh != nil else { return nil }

        return StoredCredential(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiry(firstValue(source, ["expiry", "expires_at", "expiresAt"]))
        )
    }

    // MARK: - Quota summary

    /// The pools the quota endpoint reports, in the order they should appear in the strip.
    ///
    /// Gemini Pro and Flash draw on one shared allowance, so there is one meter per window rather
    /// than one per model; every non-Gemini model shares the second pool, which the API calls `3p`
    /// ("third party") and Antigravity's own UI calls Claude.
    private static let pools: [(bucketID: String, id: String, label: String)] = [
        ("gemini-5h", "antigravity.session", "Session"),
        ("gemini-weekly", "antigravity.weekly", "Weekly"),
        ("3p-5h", "antigravity.claude", "Claude"),
        ("3p-weekly", "antigravity.claudeWeekly", "Claude Weekly"),
    ]

    package static let providerID = "antigravity"
    package static let providerName = "Antigravity"

    /// Maps a quota-summary response body to meters.
    ///
    /// Returns nil when the body isn't a quota summary at all (undecodable, or carrying no `groups`)
    /// — the caller reports that as "this build doesn't serve quota summaries yet" rather than as an
    /// empty success, which would blank a strip that had good numbers a moment ago. An empty array
    /// means the summary was understood but named no pool we know.
    ///
    /// Parsing is deliberately lenient per bucket: one malformed entry drops its own meter and
    /// leaves the rest standing. It is deliberately strict about identity — a pool is matched by
    /// exact `bucketId` and never inferred from a display name, so a future bucket cannot quietly
    /// join a pool and misreport it.
    package static func metrics(fromSummary data: Data) -> [AgentUsageMetric]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        // Accept the bare payload and a `{"response": …}` envelope; the extra lookup costs nothing.
        let body = (root["response"] as? [String: Any]) ?? root
        guard let groups = body["groups"] as? [[String: Any]] else { return nil }

        var found: [String: (fraction: Double, resetsAt: Date?)] = [:]
        for group in groups {
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard let id = bucket["bucketId"] as? String,
                      pools.contains(where: { $0.bucketID == id }),
                      found[id] == nil,
                      let fraction = number(bucket["remainingFraction"]),
                      fraction.isFinite
                else { continue }
                found[id] = (fraction, expiry(bucket["resetTime"]))
            }
        }

        return pools.compactMap { pool in
            guard let entry = found[pool.bucketID] else { return nil }
            return AgentUsageMetric(
                id: pool.id,
                providerID: providerID,
                providerName: providerName,
                label: pool.label,
                percentUsed: percentUsed(remainingFraction: entry.fraction),
                resetsAt: entry.resetsAt
            )
        }
    }

    /// The endpoint reports how much of the allowance is **left** (1 = untouched); the strip shows
    /// how much is **used**. Inverting in one named place keeps that easy to see and to test.
    package static func percentUsed(remainingFraction: Double) -> Int {
        guard remainingFraction.isFinite else { return 0 }
        // Clamp in `Double` space, before the conversion: `Int(_: Double)` traps on anything outside
        // `Int`'s range, so clamping afterwards would turn an absurd fraction — say `-1e300`, which
        // is finite and survives the guard — into a crash driven by a server response.
        let used = ((1 - remainingFraction) * 100).rounded()
        return Int(min(100, max(0, used)))
    }

    // MARK: - Value helpers

    private static func trimmed(_ value: String?) -> String? {
        // Keychain blobs occasionally carry a BOM, which would survive a plain whitespace trim and
        // break the leading `{` check below.
        let boundary = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
        guard let text = value?.trimmingCharacters(in: boundary), !text.isEmpty else { return nil }
        return text
    }

    private static func firstValue(_ object: [String: Any], _ keys: [String]) -> Any? {
        keys.lazy.compactMap { object[$0] }.first
    }

    private static func firstString(_ object: [String: Any], _ keys: [String]) -> String? {
        keys.lazy.compactMap { trimmed(object[$0] as? String) }.first
    }

    /// Reads a JSON number that may arrive as a number or as a numeric string.
    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    /// Timestamps arrive as ISO-8601, with or without fractional seconds. Epoch numbers are accepted
    /// too so a format change costs a reset countdown, not the whole meter.
    private static func expiry(_ value: Any?) -> Date? {
        if let text = trimmed(value as? String) {
            return iso8601(fractionalSeconds: true).date(from: text)
                ?? iso8601(fractionalSeconds: false).date(from: text)
        }
        guard let number = number(value), number.isFinite else { return nil }
        // Below ~1e10 the value can only sensibly be seconds; above it, milliseconds.
        let seconds = abs(number) < 1e10 ? number : number / 1000
        // A quota window resetting outside this range is a broken timestamp, not a date. Rejecting
        // it here means no `Date` far enough out to overflow the arithmetic downstream is ever
        // built — `resetNote` clamps as well, but a value this wrong should cost the countdown, not
        // be rendered as though it meant something.
        guard abs(seconds) < 1e11 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Built per call rather than cached in a static: `ISO8601DateFormatter` isn't `Sendable`, and a
    /// handful of allocations per refresh is cheaper than the synchronization sharing one would need.
    private static func iso8601(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
