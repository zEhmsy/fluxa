import Foundation
import FluxaCore
import Security
import LocalAuthentication

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
                "\(agent) credential access was not allowed. Retry from Permissions & First Run; "
                    + "choose Always Allow only if you trust this copy of Fluxa."
            case .unreadable(let agent):
                "\(agent): stored credentials are unreadable. Sign in again."
            }
        }
    }

    /// Reads one generic-password item.
    ///
    /// Returns nil when there is simply no such item, and throws when macOS refused the read — a
    /// refusal also clears the recorded approval, so the next attempt goes back through the setup
    /// button instead of prompting from a timer.
    private static func readGenericPassword(
        service: String,
        account: String?,
        requestAccess: Bool,
        agent: String,
        approvalKey: String
    ) throws -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = !requestAccess

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        if let account { query[kSecAttrAccount as String] = account }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            // Only an actual refusal revokes the recorded approval. `errSecInteractionNotAllowed` is
            // the expected answer whenever a noninteractive read would have needed a prompt — a
            // locked screen, a locked login keychain — and treating that as a denial would make an
            // idle Mac quietly discard consent the user has to grant again by hand.
            if Self.deniedStatuses.contains(status) {
                UserDefaults.standard.removeObject(forKey: approvalKey)
            }
            throw AccessError.notAllowed(agent: agent)
        }
        return item as? Data
    }

    /// Statuses that mean the user, or the ACL, said no — as opposed to "not right now".
    private static let deniedStatuses: Set<OSStatus> = [
        errSecUserCanceled, errSecAuthFailed, errSecInteractionRequired,
    ]

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

    // This is permission to ATTEMPT a read, never proof that macOS granted access. Associate the
    // opt-in with the actual signing requirement so a new ad-hoc build cannot prompt from a timer.
    //
    // It is anti-accident, not anti-tamper: the value lives in UserDefaults, so anything already
    // running as this user could write the current requirement into it. The Keychain ACL, which
    // that cannot forge, remains the boundary that actually protects the credential.
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
    /// The legacy login Keychain still owns its ACL/unlock dialogs; this is not a permanent grant.
    static func loadClaude(requestAccess: Bool = false) throws -> ClaudeCredentials? {
        readLock.lock()
        defer { readLock.unlock() }
        let json: [String: Any]?
        if let file = readClaudeFile() {
            json = file
        } else {
            if !requestAccess {
                guard hasApproval(approvalKey) else {
                    throw AccessError.approvalNeeded(agent: "Claude")
                }
            }
            json = try readClaudeKeychain(requestAccess: requestAccess)
            if requestAccess, json != nil {
                recordApproval(approvalKey)
            }
        }
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
    private static func readClaudeKeychain(requestAccess: Bool) throws -> [String: Any]? {
        for account in [NSUserName(), nil] {
            // A refusal throws straight out of the loop rather than trying the next account shape:
            // falling back after a denial/cancel can duplicate the dialog.
            guard let data = try readGenericPassword(
                service: claudeKeychainService,
                account: account,
                requestAccess: requestAccess,
                agent: "Claude",
                approvalKey: approvalKey
            ) else { continue }

            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            return json
        }
        return nil
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

    // MARK: - Antigravity

    /// Written by the Antigravity app / `agy`. Note the service is `gemini`, not `antigravity` —
    /// the account is what distinguishes it.
    private static let antigravityKeychainService = "gemini"
    private static let antigravityKeychainAccount = "antigravity"
    /// Deliberately separate from Claude's key: consenting to read one agent's credential must
    /// never imply consent for the other.
    private static let antigravityApprovalKey = "fluxa.antigravityCredentialApprovedRequirement"

    /// Same contract as `loadClaude`: only the setup button may initiate first access, ordinary
    /// refreshes require a recorded approval and never raise a dialog.
    ///
    /// Unlike Claude and Codex this credential is *derived from* rather than merely read — see
    /// `AntigravityUsageReader` for the refresh, which still never writes back to this item.
    static func loadAntigravity(requestAccess: Bool = false) throws -> AntigravityQuota.StoredCredential? {
        readLock.lock()
        defer { readLock.unlock() }

        if !requestAccess {
            guard hasApproval(antigravityApprovalKey) else {
                throw AccessError.approvalNeeded(agent: "Antigravity")
            }
        }

        guard let data = try readGenericPassword(
            service: antigravityKeychainService,
            account: antigravityKeychainAccount,
            requestAccess: requestAccess,
            agent: "Antigravity",
            approvalKey: antigravityApprovalKey
        ) else { return nil }

        if requestAccess { recordApproval(antigravityApprovalKey) }

        guard let raw = String(data: data, encoding: .utf8) else {
            throw AccessError.unreadable(agent: "Antigravity")
        }
        guard let credential = AntigravityQuota.credential(fromKeychainValue: raw) else {
            throw AccessError.unreadable(agent: "Antigravity")
        }
        return credential
    }
}
