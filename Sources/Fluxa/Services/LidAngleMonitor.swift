import IOKit
import AppKit
import QuartzCore
import Observation

// MARK: - LidAngleMonitor

/// Reads the MacBook lid angle from IORegistry (AppleHIDTopCase service) at 60 fps
/// using CADisplayLink for maximum smoothness.
///
/// The `LidAngle` IORegistry property is an integer in raw hardware units.
/// Observed range: ~0 (closed) → ~16384 (180°). Conversion: degrees = raw * 180 / 16384.
/// If the service or property is not found (e.g. desktop Macs), `isAvailable` is false.
@Observable
@MainActor
final class LidAngleMonitor {

    // MARK: - Observable State

    /// Current lid angle in degrees (0 = closed, 90 = vertical, 180 = fully open).
    private(set) var angleDegrees: Double = 0

    /// True when the IORegistry service is found and LidAngle is readable.
    private(set) var isAvailable: Bool = false

    // MARK: - Private

    /// Raw IOService handle kept open for repeated reads (avoids lookup overhead).
    private var service: io_service_t = IO_OBJECT_NULL

    /// Display link target helper (CADisplayLink needs an NSObject with @objc selector).
    private var displayLinkTarget: DisplayLinkTarget?
    private var displayLink: CADisplayLink?

    // MARK: - Init

    init() {
        openService()
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
    }

    /// Stops polling and releases the display link.
    func stopPolling() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
        if service != IO_OBJECT_NULL {
            IOObjectRelease(service)
            service = IO_OBJECT_NULL
        }
    }

    // MARK: - IOKit

    private func openService() {
        // Try "AppleHIDTopCase" first (Intel + Apple Silicon with HID bridge).
        // Fall back to "AppleTopCase" for older models.
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

    private func updateAngle() {
        guard let raw = queryRaw() else { return }
        // Raw hardware unit → degrees.
        // Empirically: raw ≈ 16384 corresponds to 180°.
        // Clamp to [0, 360] to handle any out-of-range hardware values.
        let degrees = (Double(raw) * 180.0 / 16384.0).clamped(to: 0...360)
        angleDegrees = degrees
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
