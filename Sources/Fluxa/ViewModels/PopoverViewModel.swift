import Foundation
import AppKit
import Observation

// MARK: - PopoverViewModel

/// Central coordinator for all Fluxa quick actions.
/// Owns service instances, manages toggle state, and surfaces errors to the UI.
@Observable
@MainActor
final class PopoverViewModel {

    // MARK: - Services

    private let keepAwake = KeepAwakeService()
    private let desktopIcons = DesktopIconService()
    private let screenSaver = ScreenSaverService()
    let screenClean = ScreenCleanService()
    let keyboardShield = KeyboardShieldService()
    private let focusMode = FocusModeService()
    let audioOutput = AudioOutputService()
    private let micMute = MicrophoneMuteService()
    let launchAtLogin = LaunchAtLoginService()
    let lidAngleMonitor = LidAngleMonitor()

    // MARK: - Observable State

    /// Boolean state for each toggle-style action, keyed by ActionID raw value.
    var toggleStates: [String: Bool] = [:]

    /// Non-nil when an error message should be shown in the UI.
    var errorMessage: String?

    /// Controls presentation of the Customize sheet.
    var isShowingCustomize = false

    /// Controls presentation of the Focus Mode onboarding sheet.
    var isShowingFocusOnboarding = false

    /// Signals PopoverRootView to open the Lid Angle monitor window.
    var isShowingLidAngle = false

    /// Whether an async action is in progress (disables controls during transitions).
    var isBusy = false

    /// Weak reference to the MenuBarExtra window, set by PopoverRootView on first appear.
    /// Used by the global hotkey to toggle the popover.
    weak var menuBarWindow: NSWindow?

    // MARK: - Computed

    /// The name of the currently active audio output device for display in the row subtitle.
    var currentOutputDeviceName: String {
        audioOutput.currentDevice?.name ?? "No device"
    }

    /// Returns a dynamic subtitle override for actions whose subtitle changes at runtime.
    /// Returns nil for actions with static subtitles (use the catalog subtitle instead).
    func dynamicSubtitle(for id: ActionID) -> String? {
        switch id {
        case .audioOutput:
            return currentOutputDeviceName
        case .micMute:
            return micMute.isAvailable ? micMute.currentInputDeviceName : "Volume control not available"
        default:
            return nil
        }
    }

    // MARK: - Settings

    private let settings: AppSettings

    // MARK: - Init

    init(settings: AppSettings) {
        self.settings = settings
        refreshStates()
        audioOutput.refresh()
        audioOutput.startMonitoring()
        // micMute starts monitoring in its own init
    }

    // MARK: - Toggle Actions

    /// Handles toggle events for stateful on/off actions.
    func toggleAction(_ id: ActionID) async {
        clearError()
        isBusy = true
        defer { isBusy = false }

        let current = toggleStates[id.rawValue] ?? false
        let desiredActive = !current

        do {
            switch id {
            case .keepAwake:
                if desiredActive { try keepAwake.activate() } else { keepAwake.deactivate() }
                toggleStates[id.rawValue] = keepAwake.isActive

            case .desktopIcons:
                if desiredActive { try await desktopIcons.activate() } else { try await desktopIcons.deactivate() }
                toggleStates[id.rawValue] = desktopIcons.isActive

            case .lockKeyboard:
                if desiredActive { keyboardShield.activate() } else { keyboardShield.deactivate() }
                toggleStates[id.rawValue] = keyboardShield.isActive

            case .micMute:
                guard micMute.isAvailable else {
                    errorMessage = "Volume control is not available for the current input device."
                    return
                }
                try micMute.toggle()
                toggleStates[id.rawValue] = micMute.isMuted

            case .focusMode:
                // Show onboarding if the user hasn't completed setup yet
                guard settings.focusModeOnboardingComplete else {
                    isBusy = false
                    isShowingFocusOnboarding = true
                    return
                }
                do {
                    if desiredActive {
                        try await focusMode.enable()
                    } else {
                        try await focusMode.disable()
                    }
                    // Optimistic state — system state not readable via public API
                    settings.focusModeEnabled = desiredActive
                    toggleStates[id.rawValue] = desiredActive
                } catch {
                    // Shortcut missing or deleted — reset onboarding so user can reinstall
                    toggleStates[id.rawValue] = current
                    settings.focusModeOnboardingComplete = false
                    isBusy = false
                    isShowingFocusOnboarding = true
                    return
                }

            default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            toggleStates[id.rawValue] = current // revert on failure
        }
    }

    // MARK: - Momentary Actions

    /// Triggers one-shot actions (Screen Saver, Screen Clean, Focus Mode).
    func triggerAction(_ id: ActionID, closePopover: (() -> Void)? = nil) async {
        clearError()
        isBusy = true
        defer { isBusy = false }

        do {
            switch id {
            case .screenSaver:
                closePopover?()
                try await Task.sleep(for: .milliseconds(200))
                try await screenSaver.perform()

            case .screenClean:
                closePopover?()
                try await Task.sleep(for: .milliseconds(200))
                screenClean.activate()

            case .lidAngle:
                isShowingLidAngle = true

            default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Audio Device Selection

    /// Switches the system audio output to the given device.
    func selectAudioDevice(_ device: AudioDevice) {
        do {
            try audioOutput.select(device)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - State Refresh

    /// Re-reads system state for all toggleable actions. Called on popover appear.
    func refreshStates() {
        toggleStates[ActionID.keepAwake.rawValue] = keepAwake.isActive
        toggleStates[ActionID.desktopIcons.rawValue] = desktopIcons.isActive
        toggleStates[ActionID.lockKeyboard.rawValue] = keyboardShield.isActive
        toggleStates[ActionID.focusMode.rawValue] = settings.focusModeEnabled
        micMute.refresh()
        toggleStates[ActionID.micMute.rawValue] = micMute.isMuted
        audioOutput.refresh()
    }

    /// Called from FocusOnboardingView when the user taps "Done".
    func completeFocusOnboarding() {
        settings.focusModeOnboardingComplete = true
        isShowingFocusOnboarding = false
    }

    // MARK: - Global Shortcut

    /// Toggles the MenuBarExtra window visibility. Called by the global hotkey.
    /// No-op if the window reference has not been captured yet (requires at least one popover open).
    func toggleMenuBarWindow() {
        guard let window = menuBarWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Cleanup (called from AppDelegate.applicationWillTerminate)

    func cleanup() {
        keepAwake.cleanup()
        screenClean.deactivate()
        keyboardShield.deactivate()
        audioOutput.stopMonitoring()
        micMute.cleanup()
        micMute.stopMonitoring()
    }

    // MARK: - Private

    private func clearError() {
        errorMessage = nil
    }
}
