import Foundation

// MARK: - SystemStatsSample

/// One pass over every source. Each field is independently optional: a Mac without GPU counters
/// still reports CPU and memory, and only the missing readings vanish from the UI.
struct SystemStatsSample: Sendable {
    var cpuUsage: Double?
    var gpuUsage: Double?
    var memoryUsage: Double?
    var cpuTemperature: Double?
    var gpuTemperature: Double?
    /// Whole-SoC temperature, published only by Macs that don't label their sensors per component.
    var dieTemperature: Double?

    static let empty = SystemStatsSample()
}

// MARK: - SystemStatsSampler

/// Owns the four sources and runs them off the main actor.
///
/// An actor rather than a plain type because the CPU sampler carries state between calls (the
/// previous tick counters) and the thermal reader caches its matched sensors — both must not be
/// touched concurrently. Isolating them here also keeps the syscalls and the IORegistry walk off the
/// main thread, so a slow IOKit call can never stutter the menu bar.
actor SystemStatsSampler {

    private var cpu = CPUUsageSampler()
    private let memory = MemorySampler()
    private let gpu = GPUUsageSampler()
    private let thermal = ThermalSensorReader()

    /// Reads every source once. Never throws: an unavailable source is a nil field.
    func sample() -> SystemStatsSample {
        let temperatures = thermal.read()
        return SystemStatsSample(
            cpuUsage: cpu.sample(),
            gpuUsage: gpu.sample(),
            memoryUsage: memory.sample(),
            cpuTemperature: temperatures.cpu,
            gpuTemperature: temperatures.gpu,
            dieTemperature: temperatures.die
        )
    }

    /// Takes the baseline reading the CPU sampler needs before it can express a percentage, so the
    /// first real sample already has a delta to work from.
    func prime() {
        _ = cpu.sample()
    }
}
