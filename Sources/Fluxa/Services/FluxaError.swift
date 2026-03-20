import Foundation
import IOKit

// MARK: - FluxaError

/// Structured errors for all Fluxa service operations.
enum FluxaError: LocalizedError {

    /// IOKit power management call returned a non-success code.
    case ioKitFailure(IOReturn)

    /// A shell subprocess exited with a non-zero status.
    case shellCommandFailed(String, Int)

    /// The system screensaver could not be launched.
    case screenSaverUnavailable

    /// A CoreAudio operation failed.
    case audioDeviceError(String)

    /// A CoreAudio microphone/input operation failed.
    case microphoneError(String)

    /// An action is not available due to platform limitations.
    case featureUnavailable(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .ioKitFailure(let code):
            return "Power management failed (IOKit error \(code)). Try restarting the app."

        case .shellCommandFailed(let cmd, let status):
            return "Command '\(cmd)' failed with exit code \(status)."

        case .screenSaverUnavailable:
            return "Could not launch the system screensaver. It may not be installed or accessible."

        case .audioDeviceError(let detail):
            return "Audio device error: \(detail)"

        case .microphoneError(let detail):
            return "Microphone error: \(detail)"

        case .featureUnavailable(let reason):
            return reason
        }
    }
}
