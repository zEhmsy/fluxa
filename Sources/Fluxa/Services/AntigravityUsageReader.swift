import CryptoKit
import Foundation
import FluxaCore

// MARK: - AntigravityUsageReader

/// Reads Antigravity's quota pools from Google's Cloud Code API, using the OAuth token the
/// Antigravity app / `agy` already stored in the login keychain.
///
/// **On the read-only rule.** `AgentCredentialStore` refuses to refresh Claude's and Codex's
/// tokens, because both providers rotate the refresh token on use: renewing behind their back
/// would invalidate the login the owning tool holds. Google's refresh grant does *not* rotate the
/// refresh token — exchanging it mints a new access token and leaves Antigravity's stored
/// credential untouched and still valid. So the invariant that matters, *never break the owning
/// tool's login*, survives a refresh here, and this reader does refresh. What it never does is
/// write to Antigravity's keychain item; derived tokens go in a file of Fluxa's own.
struct AntigravityUsageReader {
    static let agentName = AntigravityQuota.providerName

    private static let signInHint = "Open Antigravity or run `agy` to sign in."

    /// Production first: the `daily-` host is Google's canary deployment, and sending the user's
    /// live token there by default would route real credentials through staging. It stays only as a
    /// fallback for production being unreachable. A 401/403 doesn't fall through — the same token
    /// would fail on either — and neither does a 429, which is the service asking us to stop, not an
    /// invitation to ask a second host the same question.
    private static let baseURLs = [
        "https://cloudcode-pa.googleapis.com",
        "https://daily-cloudcode-pa.googleapis.com",
    ]
    /// The only endpoint that reports the merged pools and the weekly windows.
    private static let quotaSummaryPath = "/v1internal:retrieveUserQuotaSummary"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    /// The Google "installed application" OAuth client the refresh grant runs under.
    ///
    /// Read from a bundle resource rather than compiled in, because it is not ours: it belongs to
    /// Antigravity, and a copy of it in a public repository is what gets such a client rotated —
    /// which would break this provider for everyone. `build.sh` copies the file in from an ignored
    /// path at packaging time; see `packaging/antigravity-client.json.example`.
    ///
    /// Absent, Fluxa still reads quota with whatever access token Antigravity already stored. Only
    /// the refresh path is lost, so a source-only build degrades to "sign in again" rather than
    /// failing to launch.
    struct ClientCredentials: Decodable {
        let clientID: String
        let clientSecret: String

        private enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case clientSecret = "client_secret"
        }
    }

    private static let clientCredentials: ClientCredentials? = {
        guard let url = Bundle.main.url(forResource: "antigravity-client", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ClientCredentials.self, from: data),
              !decoded.clientID.isEmpty, !decoded.clientSecret.isEmpty
        else { return nil }
        return decoded
    }()

    private let cache = AntigravityTokenCache.shared

    // MARK: - Fetch

    func fetch() async throws -> [AgentUsageMetric] {
        // Throws `approvalNeeded` before touching the keychain when consent was never given, so the
        // background loop can never raise a dialog. Losing access — consent withdrawn, or the
        // credential gone — also drops the derived token: it would otherwise outlive the permission
        // it was minted under, for as long as it had left to run.
        let stored: AntigravityQuota.StoredCredential?
        do {
            stored = try AgentCredentialStore.loadAntigravity()
        } catch {
            await cache.discard()
            throw error
        }
        guard let credential = stored else {
            await cache.discard()
            throw AgentUsageReadError.notLoggedIn(agent: Self.agentName, hint: Self.signInHint)
        }

        // Cheapest first: a token we already derived, then the one Antigravity stored, and only
        // then an OAuth round trip.
        var candidates: [String] = []
        if let cached = await cache.token(matching: credential) { candidates.append(cached) }
        if credential.hasUsableAccessToken(), let stored = credential.accessToken {
            candidates.append(stored)
        }

        for token in candidates {
            switch await requestSummary(token: token) {
            case .ok(let data):
                await cache.clearBackoff()
                return try Self.metrics(from: data)
            case .authFailed:
                // Stale despite looking live. Drop the cached copy so the next cycle doesn't spend a
                // request rediscovering that, then fall through to a refresh.
                await cache.discard()
                continue
            case .unavailable:
                throw AgentUsageReadError.temporarilyUnavailable(agent: Self.agentName)
            }
        }

        return try await fetchAfterRefresh(credential)
    }

    private func fetchAfterRefresh(_ credential: AntigravityQuota.StoredCredential) async throws -> [AgentUsageMetric] {
        guard let refreshToken = credential.refreshToken else {
            // Nothing left to try: the access token failed and there's no way to mint another.
            throw AgentUsageReadError.tokenExpired(agent: Self.agentName, hint: Self.signInHint)
        }
        // A login that is genuinely dead fails identically every cycle. Without this the refresh
        // loop would mint a token and have it rejected every few minutes, forever, hammering
        // Google's token endpoint on the user's behalf while showing them an error re-signing-in
        // wouldn't clear.
        guard await cache.mayAttemptRefresh(for: credential) else {
            throw AgentUsageReadError.tokenExpired(agent: Self.agentName, hint: Self.signInHint)
        }

        let accessToken: String
        switch await refreshAccessToken(refreshToken) {
        case .refreshed(let token, let expiresIn):
            accessToken = token
            // Deliberately not cached yet: a token the summary endpoint goes on to reject is worse
            // than no cache at all, since it costs an extra rejected request next cycle.
            switch await requestSummary(token: accessToken) {
            case .ok(let data):
                await cache.store(accessToken, expiresIn: expiresIn, refreshToken: refreshToken)
                await cache.clearBackoff()
                return try Self.metrics(from: data)
            case .authFailed:
                // A token minted seconds ago was still rejected — the account, not the token, is
                // the problem, so back off exactly as for a dead refresh token.
                await cache.recordAuthFailure(for: credential)
                throw AgentUsageReadError.tokenExpired(agent: Self.agentName, hint: Self.signInHint)
            case .unavailable:
                throw AgentUsageReadError.temporarilyUnavailable(agent: Self.agentName)
            }
        case .authFailed:
            await cache.discard()
            await cache.recordAuthFailure(for: credential)
            throw AgentUsageReadError.tokenExpired(agent: Self.agentName, hint: Self.signInHint)
        case .unavailable:
            throw AgentUsageReadError.temporarilyUnavailable(agent: Self.agentName)
        }
    }

    private static func metrics(from data: Data) throws -> [AgentUsageMetric] {
        guard let metrics = AntigravityQuota.metrics(fromSummary: data) else {
            throw AgentUsageReadError.unsupported(
                agent: agentName,
                hint: "this build doesn't report quota summaries yet. Update Antigravity."
            )
        }
        return metrics
    }

    // MARK: - Network

    private enum SummaryOutcome {
        case ok(Data)
        /// The token was rejected. Refreshing might help; another host will not.
        case authFailed
        /// Everything else — transport failure, 5xx, an unexpected status.
        case unavailable
    }

    private func requestSummary(token: String) async -> SummaryOutcome {
        for base in Self.baseURLs {
            if Task.isCancelled { return .unavailable }
            guard let url = URL(string: base + Self.quotaSummaryPath) else { continue }

            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("Fluxa", forHTTPHeaderField: "User-Agent")
            request.httpBody = Data("{}".utf8)

            guard let (data, response) = try? await Self.session.data(for: request),
                  let http = response as? HTTPURLResponse
            else { continue }

            if http.statusCode == 401 || http.statusCode == 403 { return .authFailed }
            if (200..<300).contains(http.statusCode) { return .ok(data) }
            // Throttling is the service asking us to stop, so asking the other host the same
            // question immediately is exactly the wrong response.
            if http.statusCode == 429 { return .unavailable }
        }
        return .unavailable
    }

    private enum RefreshOutcome {
        case refreshed(accessToken: String, expiresIn: TimeInterval)
        /// The refresh token itself is dead — revoked, or the user signed out.
        case authFailed
        case unavailable
    }

    private func refreshAccessToken(_ refreshToken: String) async -> RefreshOutcome {
        // No client, no grant. Reported as a dead token rather than a transient outage: retrying
        // cannot make the credentials appear, and the sign-in hint is the only useful next step.
        guard let client = Self.clientCredentials else { return .authFailed }

        var request = URLRequest(url: Self.tokenURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            [
                "grant_type=refresh_token",
                "client_id=\(Self.formEncoded(client.clientID))",
                "client_secret=\(Self.formEncoded(client.clientSecret))",
                "refresh_token=\(Self.formEncoded(refreshToken))",
            ].joined(separator: "&").utf8
        )

        guard let (data, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .unavailable }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        switch http.statusCode {
        case 200..<300:
            guard let json,
                  let token = (json["access_token"] as? String)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty
            else {
                return .unavailable // 2xx we can't read is a server-side oddity, not a dead login
            }
            return .refreshed(accessToken: token, expiresIn: Self.lifetime(json["expires_in"]))
        default:
            // Classify on the OAuth error code, not the status: 4xx also covers throttling
            // (`rateLimitExceeded`) and a moved endpoint, and calling either of those a dead login
            // tells the user to re-sign-in for something re-signing-in cannot fix — while
            // discarding a cached token that was still perfectly good.
            let code = (json?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.terminalOAuthErrors.contains(code ?? "") ? .authFailed : .unavailable
        }
    }

    private static func formEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// The only OAuth error codes that mean the grant itself is finished. Everything else is
    /// something that may work on the next cycle.
    private static let terminalOAuthErrors: Set<String> = [
        "invalid_grant", "invalid_client", "unauthorized_client",
    ]

    /// `expires_in` may arrive as a number or a numeric string, and is clamped: a bogus large value
    /// would otherwise pin a dead token in the cache and cost a rejected request every cycle until
    /// some later refresh happened to overwrite it.
    private static func lifetime(_ value: Any?) -> TimeInterval {
        let raw: Double
        if let number = value as? NSNumber {
            raw = number.doubleValue
        } else if let string = value as? String, let parsed = Double(string) {
            raw = parsed
        } else {
            raw = 3600
        }
        guard raw.isFinite else { return 3600 }
        return min(max(raw, 0), 3600)
    }

    // MARK: - Session

    /// A session of Fluxa's own rather than `URLSession.shared`.
    ///
    /// Two reasons. Redirects are refused outright: `URLSession` replays manually-set headers onto
    /// the redirected request, including across hosts, so a 30x from either endpoint would forward
    /// the user's bearer token — or re-POST the refresh token — to whatever `Location` named.
    /// Neither of these endpoints legitimately redirects. And it is ephemeral with cookies and
    /// caching off, so credential traffic shares no state with the rest of the app.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: RedirectRefusing(), delegateQueue: nil)
    }()
}

/// Stateless, so sharing one instance across every request is safe.
private final class RedirectRefusing: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // nil = don't follow; the caller sees the 30x, which none of its status checks accept.
        completionHandler(nil)
    }
}

// MARK: - AntigravityTokenCache

/// Fluxa's own store for access tokens derived from Antigravity's refresh token, so a refresh costs
/// one OAuth exchange per token lifetime rather than one per refresh cycle.
///
/// An actor because two refreshes can overlap and a half-written file would be read back as
/// corrupt. Antigravity's keychain item is never touched from here — only this file is.
private actor AntigravityTokenCache {
    static let shared = AntigravityTokenCache()

    /// Treat a token with less than this left as spent: spending a request on it earns a near
    /// certain 401 and a second round trip.
    private static let expiryBuffer: TimeInterval = 60

    private struct Entry: Codable {
        let accessToken: String
        let expiresAt: Date
        /// Which refresh credential produced this token. Without it, a token derived for one
        /// account could be replayed after the user signs in as another.
        let credentialFingerprint: Data
    }

    private var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Fluxa/antigravity/auth.json")
    }

    /// The cached token, but only when it was derived from the refresh credential currently in the
    /// keychain and still has useful life left. Anything else is discarded rather than kept around.
    func token(matching credential: AntigravityQuota.StoredCredential) -> String? {
        guard let expected = Self.fingerprint(of: credential.refreshToken) else {
            discard()
            return nil
        }
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            discard()
            return nil
        }
        guard entry.credentialFingerprint == expected,
              entry.expiresAt.timeIntervalSinceNow > Self.expiryBuffer,
              !entry.accessToken.isEmpty
        else {
            discard()
            return nil
        }
        return entry.accessToken
    }

    func store(_ accessToken: String, expiresIn: TimeInterval, refreshToken: String) {
        guard let fileURL,
              let fingerprint = Self.fingerprint(of: refreshToken),
              !accessToken.isEmpty
        else { return }

        let entry = Entry(
            accessToken: accessToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            credentialFingerprint: fingerprint
        )
        // A failed write only costs another exchange next cycle, so nothing here is fatal — but a
        // write that lands with the wrong permissions is not "not fatal", so that path discards.
        do {
            let manager = FileManager.default
            try manager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoded = try JSONEncoder().encode(entry)

            // Created 0600 up front rather than written and then chmod'ed. `Data.write(.atomic)`
            // makes its temporary file with the default 0644-and-umask, leaving a window in which a
            // bearer token is on disk readable by every other UID on the machine.
            let staging = fileURL.deletingLastPathComponent()
                .appendingPathComponent("auth.\(UUID().uuidString).tmp")
            guard manager.createFile(
                atPath: staging.path,
                contents: encoded,
                attributes: [.posixPermissions: 0o600]
            ) else {
                discard()
                return
            }
            do {
                _ = try manager.replaceItemAt(fileURL, withItemAt: staging)
            } catch {
                try? manager.removeItem(at: staging)
                throw error
            }
        } catch {
            discard()
        }
    }

    func discard() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Backoff

    /// How long to wait after the first hard authentication failure, doubling per consecutive
    /// failure up to `maximumBackoff`.
    private static let initialBackoff: TimeInterval = 5 * 60
    private static let maximumBackoff: TimeInterval = 60 * 60

    /// Kept in memory rather than on disk: a relaunch is a reasonable moment to try again, and this
    /// exists to stop a loop, not to remember a verdict.
    private var blockedFingerprint: Data?
    private var blockedUntil: Date?
    private var consecutiveAuthFailures = 0

    /// False while a login that already failed authentication is still inside its backoff window.
    /// A different credential — the user signed in again — always gets an immediate attempt.
    func mayAttemptRefresh(for credential: AntigravityQuota.StoredCredential) -> Bool {
        guard let fingerprint = Self.fingerprint(of: credential.refreshToken) else { return true }
        guard blockedFingerprint == fingerprint, let blockedUntil else { return true }
        return Date() >= blockedUntil
    }

    func recordAuthFailure(for credential: AntigravityQuota.StoredCredential) {
        let fingerprint = Self.fingerprint(of: credential.refreshToken)
        if blockedFingerprint != fingerprint {
            blockedFingerprint = fingerprint
            consecutiveAuthFailures = 0
        }
        consecutiveAuthFailures += 1
        let delay = Self.initialBackoff * pow(2, Double(consecutiveAuthFailures - 1))
        blockedUntil = Date().addingTimeInterval(min(delay, Self.maximumBackoff))
    }

    /// Any successful read clears the backoff, whichever credential produced it.
    func clearBackoff() {
        guard blockedFingerprint != nil else { return }
        blockedFingerprint = nil
        blockedUntil = nil
        consecutiveAuthFailures = 0
    }

    private static func fingerprint(of refreshToken: String?) -> Data? {
        guard let refreshToken, !refreshToken.isEmpty else { return nil }
        return Data(SHA256.hash(data: Data(refreshToken.utf8)))
    }
}
