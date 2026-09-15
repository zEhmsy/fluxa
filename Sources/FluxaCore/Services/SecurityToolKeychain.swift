import Foundation

// MARK: - SecurityToolKeychain

/// Interacts with `/usr/bin/security` generic-password items using injected execution.
///
/// Encapsulates the argument shapes and exit-code semantics required to read credentials
/// safely without hardcoding process management or system dependencies inside FluxaCore.
package struct SecurityToolKeychain: Sendable {

    package typealias KeychainCommandRunner =
        @Sendable ([String]) throws -> (status: Int32, standardOutput: Data)

    package static let defaultService = "Claude Code-credentials"

    package enum Error: Swift.Error, Sendable, Equatable, LocalizedError {
        case notAllowed(status: Int32)
        case executionFailed(String)
        case timeout

        package var errorDescription: String? {
            switch self {
            case .notAllowed(let status):
                return "Security tool exited with non-zero status \(status)."
            case .executionFailed(let detail):
                return "Security tool execution failed: \(detail)"
            case .timeout:
                return "Security tool timed out."
            }
        }
    }

    private let runner: KeychainCommandRunner

    package init(runner: @escaping KeychainCommandRunner) {
        self.runner = runner
    }

    /// Reads generic password for Claude Code using `/usr/bin/security` argument shapes.
    ///
    /// Argument shape 1:
    /// `["find-generic-password", "-s", service, "-a", account, "-w"]`
    ///
    /// If that call exits 44 (item not found), retries argument shape 2:
    /// `["find-generic-password", "-s", service, "-w"]`
    ///
    /// - Returns: `Data` on exit 0; `nil` on exit 44 (not found).
    /// - Throws: `SecurityToolKeychain.Error.notAllowed` on non-zero exit status other than 44,
    ///   or any error thrown by the runner closure.
    package func readClaudeCredential(
        service: String = defaultService,
        account: String? = NSUserName()
    ) throws -> Data? {
        if let account, !account.isEmpty {
            let firstArgs = ["find-generic-password", "-s", service, "-a", account, "-w"]
            let (firstStatus, firstOutput) = try runner(firstArgs)
            if firstStatus == 0 {
                return firstOutput
            }
            guard firstStatus == 44 else {
                throw Error.notAllowed(status: firstStatus)
            }
        }

        let secondArgs = ["find-generic-password", "-s", service, "-w"]
        let (secondStatus, secondOutput) = try runner(secondArgs)
        if secondStatus == 0 {
            return secondOutput
        }
        if secondStatus == 44 {
            return nil
        }
        throw Error.notAllowed(status: secondStatus)
    }
}
