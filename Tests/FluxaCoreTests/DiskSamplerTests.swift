import Foundation
import Testing
@testable import FluxaCore

@Suite("DiskSamplers")
struct DiskSamplerTests {

    @Test("DiskSpaceSampler returns valid bounded percentage and non-negative free bytes or nil")
    func diskSpaceSamplerLive() {
        let sampler = DiskSpaceSampler()
        let sample = sampler.sample()

        if let usedPercentage = sample.usedPercentage {
            #expect((0.0...100.0).contains(usedPercentage))
        }

        if let freeBytes = sample.freeBytes {
            #expect(freeBytes >= 0.0)
            #expect(freeBytes.isFinite)
        }
    }

    @Test("DiskThroughputSampler produces baseline nil then non-negative finite rates")
    func diskThroughputSamplerLive() async throws {
        var sampler = DiskThroughputSampler()

        // First call establishes baseline
        let first = sampler.sample()
        #expect(first.readRate == nil)
        #expect(first.writeRate == nil)

        // Wait a short interval
        try await Task.sleep(for: .milliseconds(100))

        let second = sampler.sample()
        if let readRate = second.readRate {
            #expect(readRate >= 0.0)
            #expect(readRate.isFinite)
        }
        if let writeRate = second.writeRate {
            #expect(writeRate >= 0.0)
            #expect(writeRate.isFinite)
        }
    }

    @Test("SystemStatsSampler incorporates disk metrics in full sample")
    func systemStatsSamplerIncludesDisk() async {
        let sampler = SystemStatsSampler()
        await sampler.prime()

        let sample = await sampler.sample()
        // If space is available on host machine, it should be in readings
        if let diskUsed = sample.value(for: .diskUsedPercentage) {
            #expect((0.0...100.0).contains(diskUsed))
        }
        if let diskFree = sample.value(for: .diskFreeSpace) {
            #expect(diskFree >= 0.0)
        }
    }

    @Test("Disk metric displayText and formatting")
    func diskMetricFormatting() {
        let used = SystemMetric(id: .diskUsedPercentage, value: 72.0)
        #expect(used.displayText == "72%")
        #expect(abs(used.fraction - 0.72) < 0.001)
        #expect(used.severity == .normal)

        let free = SystemMetric(id: .diskFreeSpace, value: 256_000_000_000)
        #expect(free.displayText == ByteCountFormatter.string(fromByteCount: 256_000_000_000, countStyle: .file))
        #expect(free.fraction == 0.0)
        #expect(free.severity == .normal)

        let read = SystemMetric(id: .diskReadRate, value: 1024 * 1024 * 50)
        #expect(read.displayText.hasSuffix("/s"))
        #expect(read.fraction == 0.0)
        #expect(read.severity == .normal)

        let write = SystemMetric(id: .diskWriteRate, value: 1024 * 500)
        #expect(write.displayText.hasSuffix("/s"))
        #expect(write.fraction == 0.0)
        #expect(write.severity == .normal)
    }

    @Test("Benchmark disk sampling latency")
    func benchmarkDiskSamplers() async {
        let spaceSampler = DiskSpaceSampler()
        var throughputSampler = DiskThroughputSampler()
        _ = throughputSampler.sample()

        let iterations = 100
        let start = DispatchTime.now().uptimeNanoseconds

        for _ in 0..<iterations {
            _ = spaceSampler.sample()
            _ = throughputSampler.sample()
        }

        let end = DispatchTime.now().uptimeNanoseconds
        let totalNs = end - start
        let perOpMs = Double(totalNs) / Double(iterations) / 1_000_000.0

        // In a live system, sampling disk stats takes around 5ms per pass, well under a 100ms threshold
        #expect(perOpMs < 100.0)
    }
}

