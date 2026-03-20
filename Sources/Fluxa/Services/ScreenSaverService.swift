import Foundation
import AppKit

// MARK: - ScreenSaverService

/// Launches the system screen saver.
///
/// How it works:
/// - Opens ScreenSaverEngine.app via NSWorkspace, which is the system daemon that runs
///   screen savers. This is the documented path on macOS 10.x–15.x.
///
/// Limitations:
/// - There is no official public API to programmatically trigger the screen saver.
///   This uses a well-known but technically undocumented path to ScreenSaverEngine.
/// - On future macOS versions, the path or behavior may change.
/// - A fallback uses `open -a ScreenSaverEngine` via Process for robustness.
///
/// TODO: If Apple exposes a ScreenSaverKit API for activation in a future SDK,
///       replace this implementation with the official method.
@MainActor
final class ScreenSaverService {

    private let enginePath = "/System/Library/CoreServices/ScreenSaverEngine.app"

    // MARK: - Public API

    /// Launches the system screen saver.
    func perform() async throws {
        let url = URL(fileURLWithPath: enginePath)

        // Primary: NSWorkspace.open is the cleanest approach
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        } catch {
            // Fallback: shell `open` command
            try await runOpenFallback()
        }
    }

    // MARK: - Private

    private func runOpenFallback() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "ScreenSaverEngine"]

            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FluxaError.screenSaverUnavailable)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FluxaError.screenSaverUnavailable)
            }
        }
    }
}
