import Foundation
import IOKit

// MARK: - GPUUsageSampler

/// Graphics load, read from the accelerator's own performance counters in the IO registry.
///
/// Unlike CPU load this is an instantaneous gauge, not a tick counter, so no delta is needed and the
/// very first sample is already valid.
///
/// The `PerformanceStatistics` dictionary is populated by the graphics driver and its keys are not
/// contractual: Apple Silicon publishes `Device Utilization %`, older discrete and integrated GPUs
/// publish `GPU Activity(%)`. Both are tried, and a Mac that publishes neither simply has no GPU
/// reading — the metric disappears rather than reporting a made-up zero.
struct GPUUsageSampler {

    private static let utilizationKeys = ["Device Utilization %", "GPU Activity(%)"]

    /// Percentage 0…100, or nil when no accelerator publishes a utilization counter.
    func sample() -> Double? {
        // IOProviderClass matching includes subclasses, so this catches AGXAccelerator on Apple
        // Silicon as well as the Intel/AMD accelerators.
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        // Highest reading across accelerators: on a Mac with both an integrated and a discrete GPU
        // the busy one is the one worth showing.
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let value = utilization(of: service) else { continue }
            best = max(best ?? 0, value)
        }
        return best
    }

    private func utilization(of service: io_registry_entry_t) -> Double? {
        guard let raw = IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        for key in Self.utilizationKeys {
            // The driver may box the counter as any numeric type; NSNumber covers all of them.
            if let number = raw[key] as? NSNumber {
                return min(max(number.doubleValue, 0), 100)
            }
        }
        return nil
    }
}
