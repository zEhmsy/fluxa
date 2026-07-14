import AppKit

// MARK: - DarkModeService

/// Toggles the system appearance between Light and Dark mode.
///
/// How it works:
/// - Sets `dark mode` on System Events' appearance preferences via `osascript`.
/// - First use triggers the macOS Automation permission prompt
///   (NSAppleEventsUsageDescription in Info.plist). If the user denies it,
///   osascript exits non-zero and the error banner explains the failure.
///
/// State is read from the global defaults domain (`AppleInterfaceStyle`), which
/// is present with value "Dark" only when Dark Mode is on. NSApp.effectiveAppearance
/// cannot be used here: the service is created during FluxaApp.init(), before
/// NSApplication exists (NSApp is still nil at that point).
@MainActor
final class DarkModeService {

    // MARK: - State

    /// True when the system is currently in Dark Mode.
    var isActive: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    // MARK: - Public API

    /// Switches the system appearance to dark (true) or light (false).
    func setDark(_ dark: Bool) async throws {
        try await ShellRunner.run("/usr/bin/osascript", [
            "-e",
            "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)",
        ])
    }
}
