import Foundation

// MARK: - ShellRunner

/// Shared helper for services that shell out to system tools (`defaults`, `killall`,
/// `osascript`). Requires an unsandboxed app.
enum ShellRunner {

    /// Runs a process and waits for completion.
    /// Throws `FluxaError.shellCommandFailed` if the exit code is non-zero.
    static func run(_ executable: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FluxaError.shellCommandFailed(executable, Int(p.terminationStatus)))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
