import Foundation

// MARK: - DockAutohideService

/// Toggles Dock auto-hiding (`com.apple.dock autohide`).
///
/// How it works:
/// - Writes `com.apple.dock autohide -bool true/false` via `defaults`.
/// - Restarts the Dock via `killall Dock` to apply immediately.
///
/// Limitation: the Dock restart briefly resets Mission Control animations.
@MainActor
final class DockAutohideService {

    // MARK: - State

    /// True when the Dock is set to auto-hide.
    var isActive: Bool {
        UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
    }

    // MARK: - Public API

    /// Enables Dock auto-hiding.
    func activate() async throws {
        try await setAutohide(true)
    }

    /// Disables Dock auto-hiding (Dock always visible).
    func deactivate() async throws {
        try await setAutohide(false)
    }

    // MARK: - Private

    private func setAutohide(_ hide: Bool) async throws {
        try await ShellRunner.run(
            "/usr/bin/defaults",
            ["write", "com.apple.dock", "autohide", "-bool", hide ? "true" : "false"]
        )
        try await ShellRunner.run("/usr/bin/killall", ["Dock"])
        // Give the Dock a moment to come back before the UI re-reads state
        try await Task.sleep(for: .milliseconds(500))
    }
}
