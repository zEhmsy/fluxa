import Foundation
import Darwin

// MARK: - NetworkThroughputSampler

/// Machine-wide network throughput derived from 64-bit routing socket counters.
///
/// Uses `sysctl(NET_RT_IFLIST2)` with `if_data64` rather than `getifaddrs` (which uses 32-bit
/// `if_data.ifi_ibytes` that wraps in under a minute on Gigabit Ethernet). Interface selection
/// is an allowlist: `en*` prefix (physical Wi-Fi/Ethernet adapters) that are `IFF_UP` and
/// not `IFF_LOOPBACK`, avoiding double-counting from tunnels (`utun*`), bridges, and virtual devices.
package struct NetworkThroughputSampler {

    private struct Baseline {
        let bytesIn: UInt64
        let bytesOut: UInt64
        let at: Date
    }

    private var previous: [String: Baseline] = [:]

    package init() {}

    /// Download and upload bytes per second, or nil for both until a baseline exists or when
    /// no active network interface is found.
    package mutating func sample() -> (downloadRate: Double?, uploadRate: Double?) {
        let current = Self.readCounters()
        guard !current.isEmpty else {
            previous = [:]
            return (nil, nil)
        }

        let now = Date()
        var totalDown = 0.0
        var totalUp = 0.0
        var anyDelta = false

        for (name, counters) in current {
            defer {
                previous[name] = Baseline(bytesIn: counters.bytesIn, bytesOut: counters.bytesOut, at: now)
            }
            guard let baseline = previous[name] else {
                continue
            }

            let elapsed = now.timeIntervalSince(baseline.at)
            guard elapsed > 0 else { continue }

            let downRate = Double(counters.bytesIn &- baseline.bytesIn) / elapsed
            let upRate = Double(counters.bytesOut &- baseline.bytesOut) / elapsed
            guard downRate.isFinite, upRate.isFinite else { continue }

            totalDown += downRate
            totalUp += upRate
            anyDelta = true
        }

        // Drop baselines for interfaces that vanished so tracking doesn't grow unbounded.
        previous = previous.filter { current[$0.key] != nil }

        guard anyDelta else { return (nil, nil) }
        return (totalDown, totalUp)
    }

    /// Reads 64-bit byte counters from active `en*` interfaces via `sysctl(NET_RT_IFLIST2)`.
    private static func readCounters() -> [String: (bytesIn: UInt64, bytesOut: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_UNSPEC, NET_RT_IFLIST2, 0]
        var length: Int = 0

        // Initial size query
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else {
            return [:]
        }

        var buffer = [UInt8](repeating: 0, count: length)
        // Retry once if an interface was added between size query and buffer fill
        if sysctl(&mib, 6, &buffer, &length, nil, 0) != 0 {
            length = 0
            guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else {
                return [:]
            }
            buffer = [UInt8](repeating: 0, count: length)
            guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else {
                return [:]
            }
        }

        var result: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        let headerSize = MemoryLayout<if_msghdr2>.size

        buffer.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset + headerSize <= length {
                let ifm = rawBuffer.load(fromByteOffset: offset, as: if_msghdr2.self)
                guard ifm.ifm_msglen > 0 else { break }

                if Int32(ifm.ifm_type) == RTM_IFINFO2 {
                    let isUp = (ifm.ifm_flags & IFF_UP) != 0
                    let isLoopback = (ifm.ifm_flags & IFF_LOOPBACK) != 0

                    if isUp && !isLoopback {
                        var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                        if if_indextoname(UInt32(ifm.ifm_index), &nameBuffer) != nil {
                            let name = String(cString: nameBuffer)
                            if name.hasPrefix("en") {
                                result[name] = (
                                    bytesIn: ifm.ifm_data.ifi_ibytes,
                                    bytesOut: ifm.ifm_data.ifi_obytes
                                )
                            }
                        }
                    }
                }

                offset += Int(ifm.ifm_msglen)
            }
        }

        return result
    }
}
