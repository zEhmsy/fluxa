import Foundation
import FluxaCore

// MARK: - AntigravityUsageReader

/// Reads Antigravity's quota pools from the language server Antigravity itself runs.
///
/// Antigravity keeps a helper process alive for the whole session and drives its own usage panel
/// through it over loopback. That process already holds the signed-in session, so Fluxa asks it for
/// the same summary rather than keeping a copy of the user's login: nothing is read from the
/// keychain, no token is derived, stored or refreshed, and the request never leaves this Mac.
///
/// The cost is that the numbers exist only while Antigravity is running. That is reported as such
/// instead of as a broken login, because opening Antigravity is the only thing that helps.
struct AntigravityUsageReader {
    static let agentName = AntigravityQuota.providerName

    private static let openHint = "Open Antigravity to show its quota."

    /// The helper answers RPCs at `/<service>/<method>`, taking and returning JSON.
    private static let summaryPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"

    /// The header the helper checks before serving anything. Without it every call is a 401, which
    /// is what stops any other local program from reading the user's quota.
    private static let tokenHeader = "x-codeium-csrf-token"

    /// The reply is a few hundred bytes. Anything remotely near this is not the endpoint we think
    /// we are talking to, and is refused rather than handed to the parser.
    private static let maximumResponseBytes = 1 << 20

    private let endpoints = AntigravityEndpointCache.shared

    // MARK: - Fetch

    func fetch() async throws -> [AgentUsageMetric] {
        // The cached endpoint first: discovery costs two process spawns, and the helper keeps the
        // same port for its whole run. A rejected or unanswered request means the cache is stale —
        // Antigravity restarted, or quit — so rediscover once and try again before giving up.
        if let cached = await endpoints.cached(),
           case .ok(let data) = await requestSummary(from: cached) {
            return try Self.metrics(from: data)
        }
        await endpoints.invalidate()

        let candidates = await Self.discover()
        guard !candidates.isEmpty else {
            throw AgentUsageReadError.notRunning(agent: Self.agentName, hint: Self.openHint)
        }

        // The helper holds more than one listening socket and only one of them serves this RPC in
        // the clear, so the working one is found by asking rather than by guessing which is which.
        var answered = false
        for endpoint in candidates {
            switch await requestSummary(from: endpoint) {
            case .ok(let data):
                await endpoints.store(endpoint)
                return try Self.metrics(from: data)
            case .rejected:
                answered = true
            case .unreachable:
                continue
            }
        }

        // Something answered and turned us down: the helper is up but refused the token read from
        // its own command line. Not a login problem, and not something a retry loop can fix, so it
        // is reported as an outage rather than as Antigravity being closed.
        throw answered
            ? AgentUsageReadError.temporarilyUnavailable(agent: Self.agentName)
            : AgentUsageReadError.notRunning(agent: Self.agentName, hint: Self.openHint)
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

    // MARK: - Discovery

    /// Detached because both steps block on a child process, and the usage refresh runs on the
    /// cooperative pool that everything else in the app shares.
    private static func discover() async -> [AntigravityEndpoint] {
        await Task.detached(priority: .utility) { AntigravityProcessScan.endpoints() }.value
    }

    // MARK: - Network

    private enum SummaryOutcome {
        case ok(Data)
        /// The helper answered and turned us down.
        case rejected
        /// Nothing answered: not running any more, or listening somewhere else.
        case unreachable
    }

    private func requestSummary(from endpoint: AntigravityEndpoint) async -> SummaryOutcome {
        guard let url = URL(string: "http://127.0.0.1:\(endpoint.port)\(Self.summaryPath)") else {
            return .unreachable
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.token, forHTTPHeaderField: Self.tokenHeader)
        request.httpBody = Data("{}".utf8)

        guard let (data, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .unreachable }

        guard (200..<300).contains(http.statusCode) else { return .rejected }
        guard data.count <= Self.maximumResponseBytes else { return .rejected }
        return .ok(data)
    }

    // MARK: - Session

    /// A session of Fluxa's own rather than `URLSession.shared`: ephemeral, with cookies and
    /// caching off, and refusing redirects. A 30x would otherwise replay the token header at
    /// whatever host `Location` named, which is the one way a loopback-only call could leave the
    /// machine.
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
        // nil = don't follow; the caller sees the 30x, which its status check rejects.
        completionHandler(nil)
    }
}

// MARK: - AntigravityEndpoint

/// Where the running helper listens and the token it expects.
private struct AntigravityEndpoint: Sendable, Equatable {
    let port: Int
    let token: String
}

// MARK: - AntigravityProcessScan

/// Runs the two system tools whose output `AntigravityLocalServer` reads.
private enum AntigravityProcessScan {

    /// Every loopback port the running helper holds, paired with its token, for the caller to try
    /// in turn. Empty when Antigravity isn't running.
    static func endpoints() -> [AntigravityEndpoint] {
        guard let table = run("/bin/ps", ["-axww", "-o", "pid=,command="]),
              let instance = AntigravityLocalServer.instance(inProcessTable: table)
        else { return [] }

        // Exit status is ignored: `lsof` reports "nothing found" as a failure, which is simply an
        // empty list here.
        guard let sockets = run(
            "/usr/sbin/lsof",
            ["-nP", "-aiTCP", "-sTCP:LISTEN", "-p", String(instance.pid)]
        ) else { return [] }

        return AntigravityLocalServer.loopbackPorts(inSocketTable: sockets)
            .map { AntigravityEndpoint(port: $0, token: instance.token) }
    }

    // MARK: - Running the tool

    /// Reads to EOF before waiting, so a reply larger than the pipe buffer can't deadlock the wait.
    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - AntigravityEndpointCache

/// Remembers the endpoint that last answered, so a refresh cycle costs one loopback request rather
/// than a scan of the process table.
///
/// In memory only, and an actor because overlapping refreshes would otherwise race on it. Nothing
/// here is written to disk: the token belongs to a process that will be gone by the next launch.
private actor AntigravityEndpointCache {
    static let shared = AntigravityEndpointCache()

    private var endpoint: AntigravityEndpoint?

    func cached() -> AntigravityEndpoint? { endpoint }

    func store(_ endpoint: AntigravityEndpoint) { self.endpoint = endpoint }

    func invalidate() { endpoint = nil }
}
