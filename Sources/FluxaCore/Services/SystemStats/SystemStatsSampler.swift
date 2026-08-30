import Foundation

// MARK: - SystemStatsSample

/// One pass over every source. Values are sparse: a Mac without GPU counters still reports CPU and
/// memory, and only the missing readings vanish from the UI.
package struct SystemStatsSample: Sendable {
    package var readings: [SystemMetricID: Double]

    package static let empty = SystemStatsSample(readings: [:])

    package func value(for id: SystemMetricID) -> Double? {
        readings[id]
    }
}

// MARK: - SystemStatsSampler

/// Owns the system-reading sources and runs them off the main actor.
///
/// An actor rather than a plain type because the CPU sampler carries state between calls (the
/// previous tick counters) and the thermal reader caches its matched sensors — both must not be
/// touched concurrently. Isolating them here also keeps the syscalls and the IORegistry walk off the
/// main thread, so a slow IOKit call can never stutter the menu bar.
package actor SystemStatsSampler {

    private var cpu = CPUUsageSampler()
    private let memory = MemorySampler()
    private let gpu = GPUUsageSampler()
    private let thermal = ThermalSensorReader()
    private let diskSpace = DiskSpaceSampler()
    private var diskThroughput = DiskThroughputSampler()
    private var network = NetworkThroughputSampler()

    package init() {}

    /// Reads every source once. Never throws: an unavailable source has no dictionary entry.
    package func sample() -> SystemStatsSample {
        let temperatures = thermal.read()
        var readings: [SystemMetricID: Double] = [:]
        readings[.cpuUsage] = cpu.sample()
        readings[.gpuUsage] = gpu.sample()
        readings[.memoryUsage] = memory.sample()
        readings[.cpuTemperature] = temperatures.cpu
        readings[.gpuTemperature] = temperatures.gpu
        readings[.dieTemperature] = temperatures.die
        let space = diskSpace.sample()
        readings[.diskUsedPercentage] = space.usedPercentage
        readings[.diskFreeSpace] = space.freeBytes
        let throughput = diskThroughput.sample()
        readings[.diskReadRate] = throughput.readRate
        readings[.diskWriteRate] = throughput.writeRate
        let net = network.sample()
        readings[.networkDownloadRate] = net.downloadRate
        readings[.networkUploadRate] = net.uploadRate
        return SystemStatsSample(readings: readings)
    }

    /// Takes the baseline reading the CPU sampler needs before it can express a percentage, so the
    /// first real sample already has a delta to work from.
    package func prime() {
        _ = cpu.sample()
        _ = diskThroughput.sample()
        _ = network.sample()
    }
}
