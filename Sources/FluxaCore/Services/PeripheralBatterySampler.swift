import Foundation
import IOKit.ps
import IOBluetooth
import CoreBluetooth

// MARK: - PeripheralBatteryReading

/// One battery snapshot for a connected non-internal power source.
package struct PeripheralBatteryReading: Identifiable, Sendable, Equatable {
    package let id: String
    package let name: String
    package let level: Int
    package let isCharging: Bool

    package init(id: String, name: String, level: Int, isCharging: Bool = false) {
        self.id = id
        self.name = name
        self.level = level
        self.isCharging = isCharging
    }
}

// MARK: - PeripheralBatterySampler

/// Reads battery-reporting accessories exposed through IOKit power sources and IOBluetooth devices.
package struct PeripheralBatterySampler {

    package init() {}

    /// Returns every non-internal source with a valid 0...100 battery level.
    package func sample() -> [PeripheralBatteryReading] {
        var results: [String: PeripheralBatteryReading] = [:]

        // 1. IOKit Power Sources (Magic Mouse, Magic Keyboard, Magic Trackpad, UPS)
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any]
                else { continue }

                let transport = description[kIOPSTransportTypeKey] as? String
                guard transport != kIOPSInternalType else { continue }

                guard let level = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue,
                      (0...100).contains(level)
                else { continue }

                let name = (description[kIOPSNameKey] as? String) ?? "Unknown accessory"
                let id = (description[kIOPSHardwareSerialNumberKey] as? String) ?? name
                let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false

                results[id] = PeripheralBatteryReading(
                    id: id,
                    name: name,
                    level: level,
                    isCharging: isCharging
                )
            }
        }

        // 2. IOBluetooth paired & connected devices (AirPods, Bluetooth headphones / headsets)
        //
        // Gated exactly like BluetoothAudioService.refresh(): without an existing grant, the first
        // `pairedDevices()` call spins up IOBluetooth's CoreBluetooth coordinator, whose
        // initialiser blocks on a semaphore that is never signalled. Called from the launch path
        // that deadlocks the main thread, so the status item is never created.
        guard BluetoothAuthorizationCache.isAllowed else { return Array(results.values) }

        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for dev in paired where dev.isConnected() {
                let name = dev.nameOrAddress ?? "Bluetooth Device"
                let address = dev.addressString ?? name

                if let single = (dev.value(forKey: "batteryPercentSingle") as? NSNumber)?.intValue,
                   (1...100).contains(single) {
                    results[address] = PeripheralBatteryReading(
                        id: address,
                        name: name,
                        level: single,
                        isCharging: false
                    )
                } else {
                    let left = (dev.value(forKey: "batteryPercentLeft") as? NSNumber)?.intValue ?? 0
                    let right = (dev.value(forKey: "batteryPercentRight") as? NSNumber)?.intValue ?? 0
                    let caseBat = (dev.value(forKey: "batteryPercentCase") as? NSNumber)?.intValue ?? 0

                    if (1...100).contains(left) && (1...100).contains(right) && left == right {
                        let budId = "\(address)-buds"
                        results[budId] = PeripheralBatteryReading(
                            id: budId,
                            name: name,
                            level: left,
                            isCharging: false
                        )
                    } else {
                        if (1...100).contains(left) {
                            let leftId = "\(address)-L"
                            results[leftId] = PeripheralBatteryReading(
                                id: leftId,
                                name: "\(name) (L)",
                                level: left,
                                isCharging: false
                            )
                        }
                        if (1...100).contains(right) {
                            let rightId = "\(address)-R"
                            results[rightId] = PeripheralBatteryReading(
                                id: rightId,
                                name: "\(name) (R)",
                                level: right,
                                isCharging: false
                            )
                        }
                    }
                    if (1...100).contains(caseBat) {
                        let caseId = "\(address)-Case"
                        results[caseId] = PeripheralBatteryReading(
                            id: caseId,
                            name: "\(name) Case",
                            level: caseBat,
                            isCharging: false
                        )
                    }
                }
            }
        }

        return Array(results.values)
    }
}

// MARK: - BluetoothAuthorizationCache

/// Remembers the Bluetooth authorization answer for a moment, because asking is expensive.
///
/// `CBManager.authorization` is an XPC round trip to `bluetoothd`: measured at 8.6 ms per call on an
/// M-series Mac, against 0.026 ms for the entire IOKit power-source traversal it guards. Asking once
/// per sample would make the guard cost three hundred times the work it protects.
///
/// The window is deliberately shorter than the sampling interval, so the cache changes how often the
/// question is asked without changing the answer anyone acts on. A permission the user has just
/// granted shows up on the next reading rather than after a relaunch, and one they have revoked
/// stops us calling into IOBluetooth just as quickly — which is the case that matters, since that
/// call is what blocks forever without a grant.
private enum BluetoothAuthorizationCache {

    private static let lifetime: TimeInterval = 3

    private static let lock = NSLock()
    nonisolated(unsafe) private static var authorization: CBManagerAuthorization?
    nonisolated(unsafe) private static var readAt: TimeInterval = 0

    /// Sampling runs on whichever thread the caller is on, so the two fields move together under a
    /// lock rather than racing a stale timestamp against a fresh value.
    static var isAllowed: Bool {
        lock.lock()
        defer { lock.unlock() }

        // Uptime rather than wall clock: it cannot jump backwards when the clock is corrected, which
        // would otherwise pin a stale answer in place.
        let now = ProcessInfo.processInfo.systemUptime
        if let authorization, now - readAt < lifetime {
            return authorization == .allowedAlways
        }

        let fresh = CBManager.authorization
        authorization = fresh
        readAt = now
        return fresh == .allowedAlways
    }
}
