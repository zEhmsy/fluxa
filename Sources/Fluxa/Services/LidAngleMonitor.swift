import IOKit.hid
import AppKit
import QuartzCore
import Observation

// MARK: - LidAngleMonitor

/// Reads the MacBook lid angle at 60 fps using CADisplayLink.
///
/// Two hardware paths, tried in order:
/// 1. **Apple Silicon (2021+)**: the lid angle sensor is a HID device
///    (usage page 0x20 Sensor, usage 0x8A Orientation, AppleSPUHIDDevice).
///    Feature report ID 1 returns 3 bytes: [reportID, lo, hi] where
///    lo|hi<<8 is the angle in whole degrees (verified: 105 at ~105°).
/// 2. **Intel MacBooks**: the `LidAngle` IORegistry property on the
///    AppleHIDTopCase/AppleTopCase service, in raw units (~16384 = 180°).
///
/// If neither is present (desktop Macs), `isAvailable` is false.
@Observable
@MainActor
final class LidAngleMonitor {

    // MARK: - Observable State

    /// Current lid angle in degrees (0 = closed, 90 = vertical, 180 = fully open).
    private(set) var angleDegrees: Double = 0

    /// True when a lid angle sensor was found and is readable.
    private(set) var isAvailable: Bool = false

    // MARK: - Private

    /// HID sensor handle (Apple Silicon path). Kept open for the object's lifetime.
    private var hidDevice: IOHIDDevice?
    /// Keeps the HID manager (and its device references) alive.
    private var hidManager: IOHIDManager?

    /// Raw IOService handle (Intel path), kept open for repeated reads.
    private var service: io_service_t = IO_OBJECT_NULL

    /// Display link target helper (CADisplayLink needs an NSObject with @objc selector).
    private var displayLinkTarget: DisplayLinkTarget?
    private var displayLink: CADisplayLink?

    // MARK: - Init

    init() {
        if openHIDSensor() {
            isAvailable = true
        } else {
            openLegacyService()
        }
        updateAngle()
    }

    // MARK: - Public API

    /// Starts 60 fps polling via CADisplayLink.
    func startPolling() {
        guard isAvailable, displayLink == nil else { return }

        let target = DisplayLinkTarget()
        target.onTick = { [weak self] in self?.updateAngle() }
        displayLinkTarget = target

        // CADisplayLink(target:selector:) is unavailable on macOS.
        // Use NSScreen.displayLink(withTarget:selector:) instead (macOS 14+).
        guard let link = NSScreen.main?.displayLink(
            target: target,
            selector: #selector(DisplayLinkTarget.tick(_:))
        ) else { return }
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: RunLoop.main, forMode: .common)
        displayLink = link
        updateAngle()
    }

    /// Stops polling and releases the display link.
    /// Sensor handles stay open so the window can be reopened later.
    func stopPolling() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
    }

    // MARK: - HID Sensor (Apple Silicon)

    private func openHIDSensor() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey: 0x20,  // Sensor
            kIOHIDPrimaryUsageKey: 0x8A,      // Orientation
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first,
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              readHIDAngle(from: device) != nil
        else { return false }

        hidManager = manager
        hidDevice = device
        return true
    }

    /// Reads feature report 1 and returns the angle in degrees, or nil on failure.
    private func readHIDAngle(from device: IOHIDDevice) -> Double? {
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(
            device, kIOHIDReportTypeFeature, CFIndex(1), &report, &length
        )
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        let raw = Int(report[1]) | (Int(report[2]) << 8)
        return Double(raw)
    }

    // MARK: - IORegistry (Intel fallback)

    private func openLegacyService() {
        // Try "AppleHIDTopCase" first (Intel with HID bridge),
        // fall back to "AppleTopCase" for older models.
        let names = ["AppleHIDTopCase", "AppleTopCase"]
        for name in names {
            let s = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching(name)
            )
            if s != IO_OBJECT_NULL {
                service = s
                isAvailable = queryRaw() != nil
                return
            }
        }
        isAvailable = false
    }

    private func queryRaw() -> Int? {
        guard service != IO_OBJECT_NULL else { return nil }
        guard let cfValue = IORegistryEntryCreateCFProperty(
            service,
            "LidAngle" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }
        return (cfValue as? NSNumber)?.intValue
    }

    // MARK: - Update

    private func updateAngle() {
        if let device = hidDevice {
            guard let degrees = readHIDAngle(from: device) else { return }
            angleDegrees = degrees.clamped(to: 0...360)
        } else if let raw = queryRaw() {
            // Raw hardware unit → degrees (~16384 = 180°).
            angleDegrees = (Double(raw) * 180.0 / 16384.0).clamped(to: 0...360)
        }
    }
}

// MARK: - DisplayLinkTarget

/// NSObject trampoline required because CADisplayLink's selector must be @objc.
private final class DisplayLinkTarget: NSObject {
    var onTick: (() -> Void)?

    @objc func tick(_ link: CADisplayLink) {
        onTick?()
    }
}

// MARK: - Comparable clamping helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
