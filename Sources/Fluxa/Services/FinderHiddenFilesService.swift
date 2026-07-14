import Foundation

// MARK: - FinderHiddenFilesService

/// Shows or hides hidden files (dotfiles) in Finder by toggling `AppleShowAllFiles`.
///
/// How it works:
/// - Writes `com.apple.finder AppleShowAllFiles -bool true/false` via `defaults`.
/// - Relaunches Finder via `killall Finder` to apply the change immediately.
///
/// Limitation: the Finder relaunch closes and reopens Finder windows (~1–2 s).
@MainActor
final class FinderHiddenFilesService {

    // MARK: - State

    /// True when hidden files are currently shown in Finder.
    var isActive: Bool {
        let value = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "AppleShowAllFiles")
        switch value {
        case let bool as Bool: return bool
        case let string as String: return (string as NSString).boolValue // legacy "YES"/"NO"
        default: return false // default: hidden files are not shown
        }
    }

    // MARK: - Public API

    /// Shows hidden files in Finder.
    func activate() async throws {
        try await setShowAllFiles(true)
    }

    /// Hides hidden files in Finder (default behavior).
    func deactivate() async throws {
        try await setShowAllFiles(false)
    }

    // MARK: - Private

    private func setShowAllFiles(_ show: Bool) async throws {
        try await ShellRunner.run(
            "/usr/bin/defaults",
            ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", show ? "true" : "false"]
        )
        try await ShellRunner.run("/usr/bin/killall", ["Finder"])
        // Wait for Finder to restart before the UI re-reads state
        try await Task.sleep(for: .milliseconds(800))
    }
}
