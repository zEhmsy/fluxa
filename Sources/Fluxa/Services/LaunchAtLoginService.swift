import ServiceManagement
import Observation

// MARK: - LaunchAtLoginService

/// Manages the "Launch at Login" registration for Fluxa using the modern
/// ServiceManagement API (macOS 13+). Requires a proper .app bundle — has no
/// effect when running directly from `swift run` or `.build/release/Fluxa`.
@Observable
@MainActor
final class LaunchAtLoginService {

    /// True when Fluxa is registered to launch at login.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app for login launch.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
