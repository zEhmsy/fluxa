import AppKit

// MARK: - FocusModeService

/// Activates / deactivates Focus Mode via user-created Shortcuts.
///
/// How it works:
/// - macOS Shortcuts app has a native "Set Focus" action that can enable any Focus profile.
/// - The user creates two shortcuts once ("Fluxa Focus On" / "Fluxa Focus Off").
/// - Fluxa triggers them via `/usr/bin/shortcuts run <name>` (public CLI, no permissions needed).
///
/// State tracking:
/// - True system Focus state is not readable via public API (no read path in UserNotifications,
///   FocusFilter, or any other public framework on macOS 13+).
/// - Fluxa tracks an optimistic local toggle state persisted in AppSettings.
@MainActor
final class FocusModeService {

    // Shortcut names must match exactly what the user creates in the Shortcuts app.
    // nonisolated so ShortcutCreator (a nonisolated enum) can reference them without warnings.
    nonisolated static let focusOnShortcutName  = "Fluxa Focus On"
    nonisolated static let focusOffShortcutName = "Fluxa Focus Off"

    // MARK: - Public API

    /// Runs the "Fluxa Focus On" shortcut.
    func enable() async throws {
        try await runShortcut(named: FocusModeService.focusOnShortcutName)
    }

    /// Runs the "Fluxa Focus Off" shortcut.
    func disable() async throws {
        try await runShortcut(named: FocusModeService.focusOffShortcutName)
    }

    // MARK: - Private

    private func runShortcut(named name: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]

            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FluxaError.shellCommandFailed(
                        "shortcuts run \"\(name)\"", Int(p.terminationStatus)
                    ))
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
