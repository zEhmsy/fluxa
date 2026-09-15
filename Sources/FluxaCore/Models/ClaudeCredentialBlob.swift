import Foundation

// MARK: - ClaudeCredentialBlob

/// Pure representation and JSON parser for Claude Code OAuth credentials.
///
/// Secret handling:
/// The input blob contains both a live access token and a long-lived refresh token.
/// Swift cannot reliably zero a `String`, so the honest boundary is: keep the blob as
/// `Data`, keep only the derived `accessToken` beyond the parse, and let `Data`'s buffer
/// go out of scope promptly. We never construct a `String` of the whole blob, never interpolate
/// it, never write it to a file, never put it in an `Error`, and never log it at any level.
package struct ClaudeCredentialBlob: Sendable, Equatable {

    package enum Error: Swift.Error, Sendable, Equatable, LocalizedError {
        case unreadable

        package var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Stored Claude credential is unreadable."
            }
        }
    }

    package let accessToken: String
    package let expiresAt: Date?
    package let subscriptionType: String?
    package let scopes: [String]

    /// False for inference-only tokens, which would get a 401 from the usage endpoint.
    package var canReadUsage: Bool {
        scopes.isEmpty || scopes.contains("user:profile")
    }

    package var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    package init(
        accessToken: String,
        expiresAt: Date? = nil,
        subscriptionType: String? = nil,
        scopes: [String] = []
    ) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.scopes = scopes
    }

    /// Parses JSON `Data` into `ClaudeCredentialBlob`.
    ///
    /// Strips trailing newlines/whitespace. If the data is empty, is non-UTF8 / hex-formatted (`0x...`),
    /// is truncated or malformed JSON, or is missing a valid `claudeAiOauth` dictionary with a non-empty
    /// `accessToken`, this throws `Error.unreadable`.
    package init(data: Data) throws {
        var trimmed = data
        while let last = trimmed.last, last == 0x0A || last == 0x0D || last == 0x20 || last == 0x09 {
            trimmed.removeLast()
        }

        guard !trimmed.isEmpty,
              let json = (try? JSONSerialization.jsonObject(with: trimmed)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = (oauth["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            throw Error.unreadable
        }

        self.accessToken = token
        if let expiresMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue {
            self.expiresAt = Date(timeIntervalSince1970: expiresMs / 1000.0)
        } else if let expiresMs = oauth["expiresAt"] as? Double {
            self.expiresAt = Date(timeIntervalSince1970: expiresMs / 1000.0)
        } else {
            self.expiresAt = nil
        }
        self.subscriptionType = oauth["subscriptionType"] as? String
        self.scopes = oauth["scopes"] as? [String] ?? []
    }
}
