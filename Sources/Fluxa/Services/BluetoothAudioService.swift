import IOBluetooth

// MARK: - BluetoothAudioDevice

/// Display model for a paired Bluetooth audio device (AirPods, headphones, speakers).
struct BluetoothAudioDevice: Identifiable, Equatable {
    /// Bluetooth address string (stable identifier).
    let id: String
    let name: String
    let isConnected: Bool
}

// MARK: - BluetoothAudioService

/// Lists paired Bluetooth audio devices and connects/disconnects them on demand —
/// One Switch-style AirPods quick-connect.
///
/// How it works:
/// - `IOBluetoothDevice.pairedDevices()` enumerates the pairing list; devices with
///   major class Audio/Video (0x04) are headphones/speakers.
/// - `openConnection()` is a blocking call, so it runs on a background task and
///   the device object is re-created from its address off the main thread.
///
/// Limitation: connecting only establishes the Bluetooth link. macOS then routes
/// audio automatically per its own device-priority rules; use the Audio Output
/// row to force a specific output.
@MainActor
final class BluetoothAudioService {

    // MARK: - State

    /// Paired audio devices, connected first, then alphabetical.
    private(set) var devices: [BluetoothAudioDevice] = []

    // MARK: - Public API

    /// Re-reads the pairing list and connection states.
    func refresh() {
        let paired = IOBluetoothDevice.pairedDevices()?.compactMap { $0 as? IOBluetoothDevice } ?? []
        devices = paired
            .filter { $0.deviceClassMajor == kBluetoothDeviceClassMajorAudio }
            .map {
                BluetoothAudioDevice(
                    id: $0.addressString ?? "",
                    name: $0.name ?? "Unknown device",
                    isConnected: $0.isConnected()
                )
            }
            .sorted {
                if $0.isConnected != $1.isConnected { return $0.isConnected }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// Connects the device if disconnected, disconnects it if connected.
    func toggleConnection(for id: String) async throws {
        guard let device = IOBluetoothDevice(addressString: id) else {
            throw FluxaError.featureUnavailable("Bluetooth device not found.")
        }

        if device.isConnected() {
            let result = device.closeConnection()
            guard result == kIOReturnSuccess else {
                throw FluxaError.featureUnavailable("Could not disconnect \(device.name ?? "device").")
            }
        } else {
            // openConnection() blocks until the link is up (or times out) — keep it
            // off the main thread. IOBluetoothDevice is not Sendable: pass the
            // address and re-resolve the device inside the background task.
            let result = await Task.detached(priority: .userInitiated) {
                IOBluetoothDevice(addressString: id)?.openConnection() ?? kIOReturnError
            }.value
            guard result == kIOReturnSuccess else {
                throw FluxaError.featureUnavailable(
                    "Could not connect \(device.name ?? "device"). Make sure it is on and nearby."
                )
            }
        }

        refresh()
    }
}
