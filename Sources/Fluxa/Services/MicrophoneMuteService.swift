import CoreAudio
import Observation

// MARK: - MicrophoneMuteService

/// Controls the default audio input device's volume to implement mute/unmute.
///
/// Uses public CoreAudio AudioHardware.h APIs — no entitlements or permissions required.
/// When muting: stores the current volume and sets it to 0.
/// When unmuting: restores the previously stored volume (defaulting to 1.0 if unknown).
///
/// If the current input device does not support volume control (e.g. some aggregate devices,
/// USB audio interfaces with hardware-only gain), the service sets `isAvailable = false`
/// and the UI should render the action as `.unavailable`.
@Observable
@MainActor
final class MicrophoneMuteService {

    // MARK: - Observable State

    /// True when the default input device's volume is set to 0.
    private(set) var isMuted: Bool = false

    /// True when the current input device supports software volume control.
    private(set) var isAvailable: Bool = false

    /// Name of the current default input device, for display in the subtitle.
    private(set) var currentInputDeviceName: String = "No input device"

    // MARK: - Private

    /// Volume saved before muting, restored on unmute.
    private var previousVolume: Float32 = 1.0

    /// CoreAudio listener for default input device changes.
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Init

    init() {
        refresh()
        startMonitoring()
    }

    // MARK: - Public API

    /// Toggles mute state. If currently muted, restores the saved volume; otherwise mutes.
    func toggle() throws {
        guard isAvailable, let deviceID = fetchDefaultInputDeviceID() else {
            throw FluxaError.microphoneError("Input device does not support volume control.")
        }

        if isMuted {
            // Unmute: restore saved volume (clamp to valid range)
            let restored = max(0.01, min(1.0, previousVolume))
            try setVolume(restored, for: deviceID)
            isMuted = false
        } else {
            // Mute: save current volume then set to 0
            previousVolume = readVolume(for: deviceID) ?? 1.0
            try setVolume(0.0, for: deviceID)
            isMuted = true
        }
    }

    /// Re-reads the current default input device state (availability, name, mute status).
    func refresh() {
        guard let deviceID = fetchDefaultInputDeviceID() else {
            isAvailable = false
            isMuted = false
            currentInputDeviceName = "No input device"
            return
        }

        currentInputDeviceName = deviceName(for: deviceID) ?? "Unknown Device"
        isAvailable = canControlVolume(deviceID: deviceID)

        if isAvailable {
            let vol = readVolume(for: deviceID) ?? 0
            isMuted = vol == 0
        } else {
            isMuted = false
        }
    }

    /// Restores the input volume to the saved level (called on cleanup if muted).
    func cleanup() {
        guard isMuted, let deviceID = fetchDefaultInputDeviceID() else { return }
        let restored = max(0.01, min(1.0, previousVolume))
        try? setVolume(restored, for: deviceID)
        isMuted = false
    }

    /// Removes the CoreAudio property listener.
    func stopMonitoring() {
        guard let block = listenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        listenerBlock = nil
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        guard listenerBlock == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        listenerBlock = block

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - CoreAudio Helpers

    private func fetchDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &deviceID
        )
        return (status == noErr && deviceID != kAudioObjectUnknown) ? deviceID : nil
    }

    /// Returns true if the device exposes a settable input volume scalar.
    private func canControlVolume(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        // Check existence
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        // Check settability
        var isSettable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        return status == noErr && isSettable.boolValue
    }

    private func readVolume(for deviceID: AudioDeviceID) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)
        return status == noErr ? volume : nil
    }

    private func setVolume(_ volume: Float32, for deviceID: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = volume
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &vol
        )
        guard status == noErr else {
            throw FluxaError.microphoneError("Failed to set input volume (OSStatus \(status))")
        }
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>? = nil
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &unmanagedName)
        guard status == noErr, let name = unmanagedName?.takeRetainedValue() else { return nil }
        return name as String
    }
}
