import Darwin
import Foundation

// MARK: - MemorySampler

/// Physical memory in use, as a share of what's installed.
///
/// "Used" is deliberately **active + wired + compressed**, which is what Activity Monitor's Memory
/// Used reports. Inactive pages are excluded: macOS keeps them around opportunistically and hands
/// them back the instant something needs them, so counting them would peg a healthy Mac at ~99% and
/// make the reading useless.
struct MemorySampler {

    /// Percentage 0…100, or nil if the kernel query fails.
    func sample() -> Double? {
        guard let stats = Self.read() else { return nil }

        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count)
                    + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize

        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }

        return min(max(used / total * 100, 0), 100)
    }

    private static func read() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        return result == KERN_SUCCESS ? stats : nil
    }
}
