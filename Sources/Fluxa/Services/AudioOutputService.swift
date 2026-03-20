import CoreAudio
import Observation

// MARK: - AudioDevice

/// Represents a macOS audio output device.
struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID  // UInt32
    let name: String
}

// MARK: - AudioOutputService

/// Enumerates available audio output devices, tracks the current default output,
/// and switches output using public CoreAudio APIs.
///
/// All CoreAudio calls used here are part of the public AudioHardware.h API.
/// No entitlements or permissions are required for default output device switching.
@Observable
@MainActor
final class AudioOutputService {

    // MARK: - Observable State

    /// All discovered audio output devices (devices with at least one output stream).
    private(set) var outputDevices: [AudioDevice] = []

    /// The currently active default output device.
    private(set) var currentDevice: AudioDevice?

    // MARK: - Private

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Public API

    /// Refreshes the device list and current default device from CoreAudio.
    func refresh() {
        let allDevices = fetchAllDeviceIDs()
        let outputs = allDevices.compactMap { id -> AudioDevice? in
            guard hasOutputStream(deviceID: id), let name = deviceName(deviceID: id) else { return nil }
            return AudioDevice(id: id, name: name)
        }
        outputDevices = outputs
        currentDevice = fetchDefaultOutputDevice().flatMap { defaultID in
            outputs.first { $0.id == defaultID }
        }
    }

    /// Sets the system default audio output device.
    func select(_ device: AudioDevice) throws {
        var deviceID = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        guard status == noErr else {
            throw FluxaError.audioDeviceError("Failed to set output device (OSStatus \(status))")
        }
        currentDevice = device
    }

    /// Registers a CoreAudio property listener that calls refresh() when the default
    /// output device or the device list changes (e.g. AirPods connected/disconnected).
    func startMonitoring() {
        guard listenerBlock == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        listenerBlock = block

        // Monitor default output changes
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            DispatchQueue.main,
            block
        )

        // Monitor device list changes (hot-plug)
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            block
        )
    }

    /// Removes the CoreAudio property listener. Call from cleanup().
    func stopMonitoring() {
        guard let block = listenerBlock else { return }

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            DispatchQueue.main,
            block
        )

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            block
        )

        listenerBlock = nil
    }

    // MARK: - CoreAudio Helpers

    /// Returns all AudioDeviceIDs known to the system.
    private func fetchAllDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }
        return ids
    }

    /// Returns true if the device has at least one output stream (i.e. it can play audio).
    private func hasOutputStream(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    /// Returns the human-readable name of an audio device, or nil if unavailable.
    private func deviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // CoreAudio returns a CFString via an Unmanaged reference.
        // We use Unmanaged<CFString> to avoid the unsafe pointer warning.
        var unmanagedName: Unmanaged<CFString>? = nil
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &unmanagedName)
        guard status == noErr, let name = unmanagedName?.takeRetainedValue() else { return nil }
        return name as String
    }

    /// Returns the AudioDeviceID of the current default output device.
    private func fetchDefaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }
}
