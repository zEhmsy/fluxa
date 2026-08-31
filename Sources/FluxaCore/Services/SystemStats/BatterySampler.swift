import Foundation
import IOKit.ps

// MARK: - BatteryReading

/// One internal-battery snapshot. Nil values mean the battery or that property is unavailable;
/// `timeRemaining == -1` means IOKit is still calculating a trustworthy estimate.
package struct BatteryReading: Sendable {
    package let level: Double?
    package let timeRemaining: Double?
    package let isOnACPower: Bool?

    package init(level: Double?, timeRemaining: Double?, isOnACPower: Bool?) {
        self.level = level
        self.timeRemaining = timeRemaining
        self.isOnACPower = isOnACPower
    }
}

// MARK: - BatterySampler

/// Reads the Mac's internal battery and debounces IOKit's naturally volatile time estimate.
package struct BatterySampler {

    private static let requiredEstimateCount = 3
    private static let maximumRelativeSpread = 0.2

    private var recentEstimates: [Double] = []

    package init() {}

    package mutating func sample() -> BatteryReading {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            recentEstimates.removeAll(keepingCapacity: true)
            return BatteryReading(level: nil, timeRemaining: nil, isOnACPower: nil)
        }

        // Find the internal battery explicitly rather than assuming list order
        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        }
        guard let description = descriptions.first(where: { dict in
            (dict[kIOPSTransportTypeKey] as? String) == kIOPSInternalType ||
            (dict[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        }) ?? descriptions.first else {
            recentEstimates.removeAll(keepingCapacity: true)
            return BatteryReading(level: nil, timeRemaining: nil, isOnACPower: nil)
        }

        if let isPresent = description[kIOPSIsPresentKey] as? Bool, !isPresent {
            recentEstimates.removeAll(keepingCapacity: true)
            return BatteryReading(level: nil, timeRemaining: nil, isOnACPower: nil)
        }

        let level = (description[kIOPSCurrentCapacityKey] as? NSNumber).flatMap { number in
            let value = number.doubleValue
            return value.isFinite && (0...100).contains(value) ? value : nil
        }
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let powerSourceState = description[kIOPSPowerSourceStateKey] as? String
        let isOnACPower = powerSourceState.map { $0 == kIOPSACPowerValue }

        let estimateKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        let rawMinutes = (description[estimateKey] as? NSNumber)?.intValue ?? -1
        let timeRemaining = debouncedSeconds(fromRawMinutes: rawMinutes)

        return BatteryReading(
            level: level,
            timeRemaining: timeRemaining,
            isOnACPower: isOnACPower
        )
    }

    /// Returns IOKit's `-1` sentinel until three consecutive estimates agree within 20%.
    private mutating func debouncedSeconds(fromRawMinutes rawMinutes: Int) -> Double {
        guard rawMinutes >= 0 else {
            recentEstimates.removeAll(keepingCapacity: true)
            return -1
        }

        let seconds = Double(rawMinutes) * 60
        recentEstimates.append(seconds)
        if recentEstimates.count > Self.requiredEstimateCount {
            recentEstimates.removeFirst()
        }

        guard recentEstimates.count == Self.requiredEstimateCount,
              let low = recentEstimates.min(),
              let high = recentEstimates.max()
        else {
            return -1
        }

        if low == 0 && high == 0 {
            return 0
        }

        guard low > 0, (high - low) / low <= Self.maximumRelativeSpread else {
            return -1
        }
        return seconds
    }
}
