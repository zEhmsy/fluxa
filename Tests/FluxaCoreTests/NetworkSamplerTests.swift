import Foundation
import Testing
@testable import FluxaCore

@Suite("NetworkSamplers")
struct NetworkSamplerTests {

    @Test("NetworkThroughputSampler establishes baseline then returns non-negative rates")
    func networkThroughputSamplerLive() async throws {
        var sampler = NetworkThroughputSampler()

        // First call establishes baseline per interface
        let first = sampler.sample()
        #expect(first.downloadRate == nil)
        #expect(first.uploadRate == nil)

        // Wait a short interval
        try await Task.sleep(for: .milliseconds(100))

        let second = sampler.sample()
        if let downloadRate = second.downloadRate {
            #expect(downloadRate >= 0.0)
            #expect(downloadRate.isFinite)
        }
        if let uploadRate = second.uploadRate {
            #expect(uploadRate >= 0.0)
            #expect(uploadRate.isFinite)
        }
    }

    @Test("SystemStatsSampler incorporates network throughput in full sample")
    func systemStatsSamplerIncludesNetwork() async {
        let sampler = SystemStatsSampler()
        await sampler.prime()

        let sample = await sampler.sample()
        if let download = sample.value(for: .networkDownloadRate) {
            #expect(download >= 0.0)
            #expect(download.isFinite)
        }
        if let upload = sample.value(for: .networkUploadRate) {
            #expect(upload >= 0.0)
            #expect(upload.isFinite)
        }
    }

    @Test("Network metric displayText and formatting")
    func networkMetricFormatting() {
        let download = SystemMetric(id: .networkDownloadRate, value: 1024 * 1024 * 15)
        #expect(download.displayText.hasSuffix("/s"))
        #expect(download.fraction == 0.0)
        #expect(download.severity == .normal)
        #expect(download.tooltip == "Download: \(download.displayText)")

        let upload = SystemMetric(id: .networkUploadRate, value: 1024 * 250)
        #expect(upload.displayText.hasSuffix("/s"))
        #expect(upload.fraction == 0.0)
        #expect(upload.severity == .normal)
        #expect(upload.tooltip == "Upload: \(upload.displayText)")

        let zero = SystemMetric(id: .networkDownloadRate, value: 0)
        #expect(zero.displayText.hasSuffix("/s"))
        #expect(zero.fraction == 0.0)
    }

    @Test("Benchmark network throughput sampling latency")
    func benchmarkNetworkSampler() async {
        var sampler = NetworkThroughputSampler()
        _ = sampler.sample()

        let iterations = 100
        let start = DispatchTime.now().uptimeNanoseconds

        for _ in 0..<iterations {
            _ = sampler.sample()
        }

        let end = DispatchTime.now().uptimeNanoseconds
        let totalNs = end - start
        let perOpMs = Double(totalNs) / Double(iterations) / 1_000_000.0

        // sysctl querying active network interfaces typically takes < 2ms, bound at 50ms
        #expect(perOpMs < 50.0)
    }
}
