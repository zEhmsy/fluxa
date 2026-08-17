import Foundation
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

    // MARK: - Claude

    /// `claude` writes to a file on Linux and to the login keychain on macOS; the file is still
    /// checked first because a manual/CI setup can put one there, and reading it costs nothing and
    /// raises no prompt.
    private static let claudeCredentialFile = "~/.claude/.credentials.json"
    /// Keychain service used by Claude Code for the production endpoint.
    private static let claudeKeychainService = "Claude Code-credentials"

    /// Loads Claude's OAuth blob. Runs off the main thread: the keychain read can block on a user
    /// authorization prompt the first time a new build of Fluxa asks for the item.
    static func loadClaude() -> ClaudeCredentials? {
        let json = readClaudeFile() ?? readClaudeKeychain()
        guard let json,
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = (oauth["accessToken"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }

        return ClaudeCredentials(
            accessToken: token,
            // `expiresAt` is epoch milliseconds.
            expiresAt: (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: oauth["subscriptionType"] as? String,
            scopes: oauth["scopes"] as? [String] ?? []
        )
    }

    private static func readClaudeFile() -> [String: Any]? {
        let path = NSString(string: claudeCredentialFile).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Reads the generic-password item, first for the current user's account and then by service
    /// alone — Claude Code has used both shapes.
    private static func readClaudeKeychain() -> [String: Any]? {
        for account in [NSUserName(), nil] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: claudeKeychainService,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true,
            ]
            if let account { query[kSecAttrAccount as String] = account }

            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            return json
        }
        return nil
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
}
