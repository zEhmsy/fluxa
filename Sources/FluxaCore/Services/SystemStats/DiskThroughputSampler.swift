import Foundation
import IOKit

// MARK: - DiskThroughputSampler

/// Machine-wide block-storage throughput derived from cumulative IOKit driver counters.
package struct DiskThroughputSampler {

    private var previous: (bytesRead: UInt64, bytesWritten: UInt64, at: Date)?

    package init() {}

    /// Read and write bytes per second, or nil for both until a baseline exists or when block
    /// storage counters are unavailable.
    package mutating func sample() -> (readRate: Double?, writeRate: Double?) {
        guard let current = Self.readCounters() else { return (nil, nil) }
        let now = Date()
        defer { previous = (current.bytesRead, current.bytesWritten, now) }
        guard let previous else { return (nil, nil) }

        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return (nil, nil) }

        let readRate = Double(current.bytesRead &- previous.bytesRead) / elapsed
        let writeRate = Double(current.bytesWritten &- previous.bytesWritten) / elapsed
        guard readRate.isFinite, writeRate.isFinite else { return (nil, nil) }
        return (readRate, writeRate)
    }

    /// Sums `Bytes (Read)` and `Bytes (Write)` across every attached block-storage driver.
    ///
    /// This deliberately includes external drives. Isolating the boot volume requires walking its
    /// BSD media registry chain back to one specific driver, which is outside this ticket. Keeping
    /// the aggregation explicit prevents this machine-wide reading from being mistaken for a
    /// boot-volume-only measurement.
    private static func readCounters() -> (bytesRead: UInt64, bytesWritten: UInt64)? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWritten: UInt64 = 0
        var foundAny = false

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            if let bytesRead = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value {
                totalRead += bytesRead
                foundAny = true
            }
            if let bytesWritten = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value {
                totalWritten += bytesWritten
                foundAny = true
            }
        }

        return foundAny ? (totalRead, totalWritten) : nil
    }
}
