import Foundation
import Testing
@testable import FluxaCore

// MARK: - Call Recorder Helper

private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [[String]] = []

    func record(_ args: [String]) {
        lock.lock()
        defer { lock.unlock() }
        records.append(args)
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}

// MARK: - ClaudeCredentialBlob Tests

@Suite("ClaudeCredentialBlob")
struct ClaudeCredentialBlobTests {

    @Test("A well-formed blob parses all fields correctly")
    func wellFormedBlob() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-ant-test-token-12345",
            "expiresAt": 1900000000000,
            "subscriptionType": "max",
            "scopes": ["user:profile", "user:inference"]
          }
        }
        """
        let data = Data(json.utf8)
        let blob = try ClaudeCredentialBlob(data: data)

        #expect(blob.accessToken == "sk-ant-test-token-12345")
        #expect(blob.expiresAt == Date(timeIntervalSince1970: 1900000000.0))
        #expect(blob.subscriptionType == "max")
        #expect(blob.scopes == ["user:profile", "user:inference"])
        #expect(blob.canReadUsage == true)
        #expect(blob.isExpired == false)
    }

    @Test("Trailing newlines and whitespace are stripped before parsing")
    func trailingWhitespaceStripped() throws {
        let json = "{\"claudeAiOauth\": {\"accessToken\": \"tok\"}}\r\n  \n"
        let blob = try ClaudeCredentialBlob(data: Data(json.utf8))
        #expect(blob.accessToken == "tok")
    }

    @Test("Hex output prefixed with 0x throws unreadable")
    func hexOutputThrowsUnreadable() {
        let hexData = Data("0x6162636465660a".utf8)
        #expect(throws: ClaudeCredentialBlob.Error.unreadable) {
            try ClaudeCredentialBlob(data: hexData)
        }
    }

    @Test("Truncated JSON throws unreadable")
    func truncatedJSONThrowsUnreadable() {
        let truncated = Data("{\"claudeAiOauth\": {\"accessToken\": \"par".utf8)
        #expect(throws: ClaudeCredentialBlob.Error.unreadable) {
            try ClaudeCredentialBlob(data: truncated)
        }
    }

    @Test("Empty data or missing accessToken throws unreadable")
    func invalidPayloadThrowsUnreadable() {
        #expect(throws: ClaudeCredentialBlob.Error.unreadable) {
            try ClaudeCredentialBlob(data: Data())
        }
        #expect(throws: ClaudeCredentialBlob.Error.unreadable) {
            try ClaudeCredentialBlob(data: Data("{}".utf8))
        }
        #expect(throws: ClaudeCredentialBlob.Error.unreadable) {
            try ClaudeCredentialBlob(data: Data("{\"claudeAiOauth\": {\"accessToken\": \"   \"}}".utf8))
        }
    }

    @Test("A blob whose scopes lack user:profile reports canReadUsage as false")
    func missingProfileScope() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "inference-token",
            "scopes": ["user:inference"]
          }
        }
        """
        let blob = try ClaudeCredentialBlob(data: Data(json.utf8))
        #expect(blob.canReadUsage == false)
    }

    @Test("A blob whose scopes include user:profile or are empty reports canReadUsage as true")
    func profileScopeOrEmpty() throws {
        let withProfile = try ClaudeCredentialBlob(data: Data("{\"claudeAiOauth\": {\"accessToken\": \"t\", \"scopes\": [\"user:profile\"]}}".utf8))
        #expect(withProfile.canReadUsage == true)

        let emptyScopes = try ClaudeCredentialBlob(data: Data("{\"claudeAiOauth\": {\"accessToken\": \"t\", \"scopes\": []}}".utf8))
        #expect(emptyScopes.canReadUsage == true)
    }

    @Test("isExpired reflects token expiration against current date")
    func expirationCalculation() throws {
        let past = try ClaudeCredentialBlob(data: Data("{\"claudeAiOauth\": {\"accessToken\": \"t\", \"expiresAt\": 1000000000000}}".utf8))
        #expect(past.isExpired == true)

        let future = try ClaudeCredentialBlob(data: Data("{\"claudeAiOauth\": {\"accessToken\": \"t\", \"expiresAt\": 4102444800000}}".utf8))
        #expect(future.isExpired == false)

        let none = try ClaudeCredentialBlob(data: Data("{\"claudeAiOauth\": {\"accessToken\": \"t\"}}".utf8))
        #expect(none.isExpired == false)
    }
}

// MARK: - SecurityToolKeychain Tests

@Suite("SecurityToolKeychain")
struct SecurityToolKeychainTests {

    @Test("Exit 44 returns nil")
    func exit44ReturnsNil() throws {
        let keychain = SecurityToolKeychain { _ in
            (status: 44, standardOutput: Data())
        }
        let result = try keychain.readClaudeCredential(account: "testuser")
        #expect(result == nil)
    }

    @Test("A non-zero exit throws an error")
    func nonZeroExitThrows() {
        let keychain = SecurityToolKeychain { _ in
            (status: 1, standardOutput: Data())
        }
        #expect(throws: SecurityToolKeychain.Error.notAllowed(status: 1)) {
            try keychain.readClaudeCredential(account: "testuser")
        }
    }

    @Test("The second argument shape is tried only after a 44 from the first")
    func fallbackOn44() throws {
        let recorder = CallRecorder()
        let expectedData = Data("{\"claudeAiOauth\":{\"accessToken\":\"tok\"}}".utf8)

        let keychain = SecurityToolKeychain { args in
            recorder.record(args)
            if args.contains("-a") {
                return (status: 44, standardOutput: Data())
            } else {
                return (status: 0, standardOutput: expectedData)
            }
        }

        let result = try keychain.readClaudeCredential(account: "testuser")
        #expect(result == expectedData)

        let calls = recorder.calls
        #expect(calls.count == 2)
        #expect(calls[0] == ["find-generic-password", "-s", "Claude Code-credentials", "-a", "testuser", "-w"])
        #expect(calls[1] == ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
    }

    @Test("First argument shape succeeding does not invoke second shape")
    func firstShapeSucceeds() throws {
        let recorder = CallRecorder()
        let expectedData = Data("{\"claudeAiOauth\":{\"accessToken\":\"tok\"}}".utf8)

        let keychain = SecurityToolKeychain { args in
            recorder.record(args)
            return (status: 0, standardOutput: expectedData)
        }

        let result = try keychain.readClaudeCredential(account: "testuser")
        #expect(result == expectedData)

        let calls = recorder.calls
        #expect(calls.count == 1)
        #expect(calls[0] == ["find-generic-password", "-s", "Claude Code-credentials", "-a", "testuser", "-w"])
    }

    @Test("First argument shape failing with non-44 throws immediately without trying second shape")
    func firstShapeErrorDoesNotFallback() {
        let recorder = CallRecorder()

        let keychain = SecurityToolKeychain { args in
            recorder.record(args)
            return (status: 2, standardOutput: Data())
        }

        #expect(throws: SecurityToolKeychain.Error.notAllowed(status: 2)) {
            try keychain.readClaudeCredential(account: "testuser")
        }

        let calls = recorder.calls
        #expect(calls.count == 1)
        #expect(calls[0] == ["find-generic-password", "-s", "Claude Code-credentials", "-a", "testuser", "-w"])
    }

    @Test("When account is nil, only second argument shape is executed")
    func nilAccountUsesSecondShapeDirectly() throws {
        let recorder = CallRecorder()
        let expectedData = Data("{\"claudeAiOauth\":{\"accessToken\":\"tok\"}}".utf8)

        let keychain = SecurityToolKeychain { args in
            recorder.record(args)
            return (status: 0, standardOutput: expectedData)
        }

        let result = try keychain.readClaudeCredential(account: nil)
        #expect(result == expectedData)

        let calls = recorder.calls
        #expect(calls.count == 1)
        #expect(calls[0] == ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
    }

    @Test("Runner throwing error rethrows to caller")
    func runnerThrowsError() {
        let keychain = SecurityToolKeychain { _ in
            throw SecurityToolKeychain.Error.timeout
        }
        #expect(throws: SecurityToolKeychain.Error.timeout) {
            try keychain.readClaudeCredential(account: "testuser")
        }
    }
}
