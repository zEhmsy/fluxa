import Foundation

// MARK: - DiskSpaceSampler

/// Space in use and available on the boot volume.
///
/// "Free" deliberately means `volumeAvailableCapacityForImportantUsage`, not raw `statfs`
/// capacity. On APFS this accounts for space macOS can honestly make available for important user
/// data, so the result follows Finder's available-capacity semantics instead of overstating space
/// through container and snapshot details.
package struct DiskSpaceSampler {

    package init() {}

    /// Used percentage and free bytes, or nil for both when the boot volume cannot be queried.
    package func sample() -> (usedPercentage: Double?, freeBytes: Double?) {
        let bootVolume = URL(fileURLWithPath: "/")
        guard let values = try? bootVolume.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]),
        let available = values.volumeAvailableCapacityForImportantUsage,
        available >= 0,
        let total = values.volumeTotalCapacity,
        total > 0 else {
            return (nil, nil)
        }

        let free = Double(available)
        let totalBytes = Double(total)
        let usedPercentage = min(max((totalBytes - free) / totalBytes * 100, 0), 100)
        return (usedPercentage, free)
    }
}
