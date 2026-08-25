import Darwin

// MARK: - CPUUsageSampler

/// Machine-wide CPU load, as the share of ticks the kernel spent doing anything other than idling.
///
/// `host_statistics(HOST_CPU_LOAD_INFO)` reports *cumulative* tick counters since boot, so a single
/// reading says nothing about right now — the load is the difference between two readings divided by
/// the total elapsed ticks. The first `sample()` after start therefore has no baseline to subtract
/// and deliberately returns nil; the caller shows the metric from the second tick onward.
struct CPUUsageSampler {

    /// Tick counters from the previous call, in the order the kernel reports them.
    private var previous: host_cpu_load_info?

    /// Busy percentage 0…100, or nil on the first call and if the kernel query fails.
    mutating func sample() -> Double? {
        guard let current = Self.read() else { return nil }
        defer { previous = current }
        guard let previous else { return nil }

        // CPU_STATE_MAX counters: user, system, idle, nice.
        let deltaUser   = Double(current.cpu_ticks.0 &- previous.cpu_ticks.0)
        let deltaSystem = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1)
        let deltaIdle   = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2)
        let deltaNice   = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3)

        let busy = deltaUser + deltaSystem + deltaNice
        let total = busy + deltaIdle
        // A tick counter that didn't move (a very short interval, or a wake from sleep that reset
        // the comparison) can't express a percentage — better no number than a fabricated 0%.
        guard total > 0 else { return nil }

        return min(max(busy / total * 100, 0), 100)
    }

    private static func read() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }

        return result == KERN_SUCCESS ? info : nil
    }
}
