import Foundation
import AppKit

// MARK: - DesktopIconService

/// Shows or hides all Finder desktop icons by toggling the `CreateDesktop` preference.
///
/// How it works:
/// - Writes `com.apple.finder CreateDesktop -bool false/true` via `defaults` CLI.
/// - Relaunches Finder via `killall Finder` to apply the change immediately.
///
/// Limitations:
/// - Hiding icons disables the *entire desktop* — files still exist but are not accessible
///   via the desktop UI until icons are restored.
/// - Finder relaunch takes ~1–2 seconds; the app may visually "flicker" during this time.
/// - macOS 14+ may cache this preference differently; killall Finder is the reliable path.
/// - This approach requires an unsandboxed app (Process/shell is blocked in sandbox).
@MainActor
final class DesktopIconService {

    // MARK: - State

    /// Returns true when desktop icons are currently hidden.
    var isActive: Bool {
        // Read directly from Finder's defaults domain.
        // CreateDesktop defaults to true (shown); false = hidden.
        let value = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop")
        if let boolValue = value as? Bool {
            return !boolValue // hidden = CreateDesktop is false
        }
        return false // default: icons are shown
    }

    // MARK: - Public API

    /// Hides all desktop icons.
    func activate() async throws {
        try await setCreateDesktop(false)
        try await relaunchFinder()
        // Wait for Finder to restart before refreshing state
        try await Task.sleep(for: .milliseconds(800))
    }

    /// Shows all desktop icons.
    func deactivate() async throws {
        try await setCreateDesktop(true)
        try await relaunchFinder()
        try await Task.sleep(for: .milliseconds(800))
    }

    // MARK: - Private

    private func setCreateDesktop(_ visible: Bool) async throws {
        try await runProcess(
            executable: "/usr/bin/defaults",
            arguments: ["write", "com.apple.finder", "CreateDesktop", "-bool", visible ? "true" : "false"]
        )
    }

    private func relaunchFinder() async throws {
        try await runProcess(
            executable: "/usr/bin/killall",
            arguments: ["Finder"]
        )
    }

    /// Runs a shell process and waits for it to complete.
    /// Throws `FluxaError.shellCommandFailed` if the exit code is non-zero.
    private func runProcess(executable: String, arguments: [String]) async throws {
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
