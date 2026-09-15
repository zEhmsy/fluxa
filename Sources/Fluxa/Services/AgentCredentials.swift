import Foundation
import FluxaCore
import Security

// MARK: - ClaudeCredentials

/// The OAuth blob Claude Code stores for the signed-in account.
struct ClaudeCredentials {
    let accessToken: String
    /// Absolute expiry of the access token, when the blob carries one.
    let expiresAt: Date?
    /// Plan name as Anthropic reports it ("pro", "max"), used for the tooltip.
    let subscriptionType: String?
    /// OAuth scopes granted to this token. Live usage needs `user:profile`; a token minted by
    /// `claude setup-token` is inference-only and can't read the usage endpoint.
    let scopes: [String]

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    /// False for inference-only tokens, which would get a 401 from the usage endpoint.
    var canReadUsage: Bool {
        scopes.isEmpty || scopes.contains("user:profile")
    }

    init(from blob: ClaudeCredentialBlob) {
        self.accessToken = blob.accessToken
        self.expiresAt = blob.expiresAt
        self.subscriptionType = blob.subscriptionType
        self.scopes = blob.scopes
    }
}

// MARK: - CodexCredentials

/// The token set the Codex CLI writes to `~/.codex/auth.json`.
struct CodexCredentials {
    let accessToken: String
    /// ChatGPT account id, sent as `ChatGPT-Account-Id`; the usage endpoint needs it on
    /// multi-account logins.
    let accountID: String?
}

// MARK: - AgentCredentialStore

/// Locates the credentials the local agent CLIs already wrote, without ever refreshing or
/// rewriting them.
///
/// **Read-only on purpose.** Both providers rotate the refresh token on use: refreshing here would
/// invalidate the token Claude Code / Codex themselves hold, breaking the very logins Fluxa is
/// reading. So an expired access token is reported as such — running the agent once mints a fresh
/// one — rather than silently renewed behind the owning tool's back.
enum AgentCredentialStore {

    enum AccessError: LocalizedError {
        case approvalNeeded(agent: String)
        case notAllowed(agent: String)
        /// The item was read, but what came out isn't a credential we can parse. Distinct from
        /// "absent": retrying won't help, so the message asks for a fresh sign-in.
        case unreadable(agent: String)

        var errorDescription: String? {
            switch self {
            case .approvalNeeded(let agent):
                "\(agent): enable credential access in Customize → Permissions & First Run."
            case .notAllowed(let agent):
                "\(agent) credential access was not allowed. Retry from Permissions & First Run."
            case .unreadable(let agent):
                "\(agent): stored credentials are unreadable. Sign in again."
            }
        }
    }

    private final class TimeoutSentinel: @unchecked Sendable {
        private let lock = NSLock()
        private var timedOut = false

        var didTimeout: Bool {
            lock.lock()
            defer { lock.unlock() }
            return timedOut
        }

        func markTimeout() {
            lock.lock()
            defer { lock.unlock() }
            timedOut = true
        }
    }

    /// Executes `/usr/bin/security` with isolated environment and bounded 5-second execution.
    ///
    /// Per Spec 19 (D2, D3, D4):
    /// - Absolute path `/usr/bin/security`, never a PATH lookup.
    /// - Environment: passes only HOME (`NSHomeDirectory()`), does not inherit DYLD_* or PATH.
    /// - stderr goes to FileHandle.nullDevice: it is diagnostic text the user cannot act on.
    /// - stdout is read to end before waitUntilExit() to prevent pipe buffer deadlock.
    /// - 5-second watchdog timer: terminates, sleeps 0.1s, kills with SIGKILL if still alive.
    /// - Reaps the process in every path, including the timeout path.
    @Sendable
    private static func runSecurityCommand(arguments: [String]) throws -> (status: Int32, standardOutput: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.environment = ["HOME": NSHomeDirectory()]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        let sentinel = TimeoutSentinel()
        let watchdog = DispatchWorkItem { [weak process] in
            guard let process else { return }
            if process.isRunning {
                sentinel.markTimeout()
                process.terminate()
                Thread.sleep(forTimeInterval: 0.1)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        do {
            try process.run()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5.0, execute: watchdog)
            let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()

            if sentinel.didTimeout {
                throw SecurityToolKeychain.Error.timeout
            }

            return (status: process.terminationStatus, standardOutput: output)
        } catch {
            watchdog.cancel()
            if process.isRunning {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.1)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
            }
            throw error
        }
    }

    /// Whether this build already has the user's consent to read `approvalKey`'s item.
    ///
    /// Consent is bound to the current code-signing requirement, so a re-signed or ad-hoc build
    /// cannot inherit it and start raising dialogs from the background refresh loop.
    private static func hasApproval(_ approvalKey: String) -> Bool {
        guard let requirement = currentSigningRequirement() else { return false }
        return UserDefaults.standard.string(forKey: approvalKey) == requirement
    }

    private static func recordApproval(_ approvalKey: String) {
        guard let requirement = currentSigningRequirement() else { return }
        UserDefaults.standard.set(requirement, forKey: approvalKey)
    }

    // The Keychain ACL for this item lists /usr/bin/security, so any process running as this user
    // can read it with one command. The in-app opt-in is now the consent point, not a convenience
    // in front of a system gate.
    //
    // Associating the opt-in with the current code-signing requirement ensures a new ad-hoc build
    // cannot prompt or read credentials from the background refresh loop without explicit user
    // action in Permissions & First Run.
    private static let approvalKey = "fluxa.claudeCredentialApprovedRequirement"
    private static let readLock = NSLock()

    // MARK: - Claude

    /// `claude` writes to a file on Linux and to the login keychain on macOS; the file is still
    /// checked first because a manual/CI setup can put one there, and reading it costs nothing and
    /// raises no prompt.
    private static let claudeCredentialFile = "~/.claude/.credentials.json"
    /// Keychain service used by Claude Code for the production endpoint.
    private static let claudeKeychainService = "Claude Code-credentials"

    /// Only the setup button may initiate first access for a code identity. Ordinary refreshes
    /// request a noninteractive context, and do not retry a rejected read in a prompt loop.
    static func loadClaude(requestAccess: Bool = false) throws -> ClaudeCredentials? {
        readLock.lock()
        defer { readLock.unlock() }

        if let fileBlob = readClaudeFile() {
            return ClaudeCredentials(from: fileBlob)
        }

        if !requestAccess {
            guard hasApproval(approvalKey) else {
                throw AccessError.approvalNeeded(agent: "Claude")
            }
        }

        guard let blob = try readClaudeKeychain() else {
            return nil
        }

        if requestAccess {
            recordApproval(approvalKey)
        }

        return ClaudeCredentials(from: blob)
    }

    private static func readClaudeFile() -> ClaudeCredentialBlob? {
        let path = NSString(string: claudeCredentialFile).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? ClaudeCredentialBlob(data: data)
    }

    /// Reads Claude Code credentials from the login keychain using SecurityToolKeychain.
    ///
    /// On success: returns parsed ClaudeCredentialBlob.
    /// On exit 44 (not found): returns nil, leaving recorded approval intact.
    /// On failure or timeout: revokes recorded approval and throws AccessError.notAllowed.
    /// On parse error: throws AccessError.unreadable.
    private static func readClaudeKeychain() throws -> ClaudeCredentialBlob? {
        let keychain = SecurityToolKeychain(runner: runSecurityCommand)
        let data: Data?
        do {
            data = try keychain.readClaudeCredential(
                service: claudeKeychainService,
                account: NSUserName()
            )
        } catch {
            UserDefaults.standard.removeObject(forKey: approvalKey)
            throw AccessError.notAllowed(agent: "Claude")
        }

        guard let data else {
            return nil
        }

        do {
            return try ClaudeCredentialBlob(data: data)
        } catch {
            throw AccessError.unreadable(agent: "Claude")
        }
    }

    private static func currentSigningRequirement() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement,
              SecRequirementCopyString(requirement, SecCSFlags(), &text) == errSecSuccess else {
            return nil
        }
        return text as String?
    }

    // MARK: - Codex

    private static let codexAuthFile = "~/.codex/auth.json"

    static func loadCodex() -> CodexCredentials? {
        let path = NSString(string: codexAuthFile).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = (tokens["access_token"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }

        return CodexCredentials(
            accessToken: token,
            accountID: tokens["account_id"] as? String
        )
    }

    // Antigravity has no entry here on purpose. Its quota comes from the helper process Antigravity
    // itself runs, which already holds the session — so Fluxa never reads, copies or renews that
    // login. See `AntigravityUsageReader`.
}
