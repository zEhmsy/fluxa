import AppKit
import ApplicationServices
import CoreBluetooth
import Observation
import UserNotifications

// MARK: - Permission Status

enum FluxaPermissionStatus: Equatable {
    case notRequested
    case granted
    case denied
    case restricted
    case unavailable

    var title: String {
        switch self {
        case .notRequested: "Not enabled"
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .restricted: "Restricted"
        case .unavailable: "Needs checking"
        }
    }
}

// MARK: - PermissionsService

/// Observes system permission state without requesting access on launch. Requests belong to
/// explicit user actions; a saved onboarding preference is never treated as an OS authorization.
@Observable
@MainActor
final class PermissionsService: NSObject, CBCentralManagerDelegate {
    private(set) var accessibility: FluxaPermissionStatus = .notRequested
    private(set) var automation: FluxaPermissionStatus = .unavailable
    private(set) var bluetooth: FluxaPermissionStatus = .notRequested
    private(set) var claude: FluxaPermissionStatus = .notRequested
    private(set) var notifications: FluxaPermissionStatus = .notRequested
    private(set) var busyPermission: String?
    private(set) var message: String?
    var showsWelcome = false

    @ObservationIgnored private var bluetoothManager: CBCentralManager?
    @ObservationIgnored private var refreshInProgress = false

    static let windowID = "permissions-setup"

    override init() {
        super.init()
        refreshImmediateStates()
    }

    /// Rechecked when this window becomes active or the user presses Refresh. No polling prompts.
    func refresh() async {
        refreshImmediateStates()
        guard !refreshInProgress, busyPermission == nil else { return }
        refreshInProgress = true
        defer { refreshInProgress = false }
        let status = await Task.detached(priority: .utility) {
            Self.automationStatus()
        }.value
        // A request may have started while the preflight was running. Do not overwrite its result.
        guard busyPermission == nil else { return }
        automation = status
    }

    func requestAccessibility() {
        guard busyPermission == nil else { return }
        message = nil
        refreshImmediateStates()
        guard accessibility != .granted else { return }
        KeyboardShieldService.requestAccessibilityIfNeeded()
        message = "Enable Fluxa in Privacy & Security → Accessibility, then return here. "
            + "If Fluxa is missing, use + and select the app in Applications. Keyboard Lock is not activated during setup."
    }

    func requestAutomation() async {
        guard busyPermission == nil else { return }
        message = nil
        if automation == .denied {
            openSettings("Privacy_Automation")
            return
        }
        guard automation != .granted else { return }
        busyPermission = "automation"
        defer { busyPermission = nil }
        do {
            // Use the same sender as DarkModeService, but read rather than change appearance.
            // osascript also starts System Events when needed; preflight alone must not launch it.
            try await ShellRunner.run("/usr/bin/osascript", [
                "-e", "tell application \"System Events\" to tell appearance preferences to get dark mode",
            ])
            automation = .granted
        } catch {
            automation = await Task.detached(priority: .utility) {
                Self.automationStatus()
            }.value
            message = "Automation was not enabled. In Privacy & Security → Automation, "
                + "expand Fluxa and enable System Events. No appearance setting was changed."
        }
    }

    func requestBluetooth() {
        guard busyPermission == nil else { return }
        message = nil
        refreshImmediateStates()
        switch bluetooth {
        case .granted:
            return
        case .denied, .restricted:
            openSettings("Privacy_Bluetooth")
        default:
            // Creating the manager is the explicit permission request. Never scan, connect,
            // or ask to turn the radio on just to show this setup screen.
            if bluetoothManager == nil {
                bluetoothManager = CBCentralManager(
                    delegate: self,
                    queue: .main,
                    options: [CBCentralManagerOptionShowPowerAlertKey: false]
                )
            }
            message = "Allow Bluetooth in the macOS dialog. If access was already denied, "
                + "enable Fluxa in Privacy & Security → Bluetooth. No device will be connected."
        }
    }

    func requestClaudeAccess() async {
        guard busyPermission == nil else { return }
        message = nil
        busyPermission = "claude"
        defer { busyPermission = nil }
        do {
            let available = try await Task.detached(priority: .userInitiated) {
                try AgentCredentialStore.loadClaude(requestAccess: true) != nil
            }.value
            claude = available ? .granted : .unavailable
            if !available {
                message = "No Claude credentials were found. Sign in with Claude Code, then try again. "
                    + "Fluxa never creates, refreshes or rewrites the agent's credentials."
            }
        } catch {
            claude = .denied
            message = error.localizedDescription
        }
    }

    func requestNotifications() async {
        guard busyPermission == nil else { return }
        message = nil
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            notifications = .granted
            return
        case .denied:
            notifications = .denied
            openSettings("Privacy_Notifications")
            return
        default:
            break
        }

        busyPermission = "notifications"
        defer { busyPermission = nil }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            notifications = granted ? .granted : .denied
            if !granted {
                message = "Notifications were not enabled. Alerts will stay silent until you allow "
                    + "them in Privacy & Security → Notifications."
            }
        } catch {
            notifications = .denied
            message = error.localizedDescription
        }
    }

    func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        if !NSWorkspace.shared.open(url) {
            message = "Open System Settings → Privacy & Security and choose the permission manually."
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in self?.refreshImmediateStates() }
    }

    private func refreshImmediateStates() {
        accessibility = AXIsProcessTrusted() ? .granted : .notRequested
        switch CBManager.authorization {
        case .allowedAlways: bluetooth = .granted
        case .denied: bluetooth = .denied
        case .restricted: bluetooth = .restricted
        case .notDetermined: bluetooth = .notRequested
        @unknown default: bluetooth = .unavailable
        }
    }

    nonisolated private static func automationStatus() -> FluxaPermissionStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false
        )
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notRequested
        // System Events may not be running; do not launch it from a passive status check.
        default: return .unavailable
        }
    }
}
