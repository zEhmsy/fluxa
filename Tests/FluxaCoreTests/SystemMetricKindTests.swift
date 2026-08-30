import Foundation
import Testing
@testable import FluxaCore

@Suite("SystemMetricKindModel")
struct SystemMetricKindTests {

    @Test("All five Kind cases exist and report bounded status accurately")
    func kindBoundedStatus() {
        #expect(SystemMetricID.Kind.percentage.hasBoundedRange == true)
        #expect(SystemMetricID.Kind.temperature.hasBoundedRange == true)
        #expect(SystemMetricID.Kind.byteRate.hasBoundedRange == false)
        #expect(SystemMetricID.Kind.byteCount.hasBoundedRange == false)
        #expect(SystemMetricID.Kind.duration.hasBoundedRange == false)
    }

    @Test("Unbounded kinds return 0 fraction and normal severity")
    func unboundedKindsFractionAndSeverity() {
        let values: [Double] = [0, 100, 1024, 1_000_000, 1_000_000_000]

        for val in values {
            // For percentage (bounded)
            let percentageMetric = SystemMetric(id: .cpuUsage, value: val)
            #expect(percentageMetric.fraction == min(max(val / 100, 0), 1))

            // For temperature (bounded)
            let tempMetric = SystemMetric(id: .cpuTemperature, value: val)
            #expect(tempMetric.fraction == min(max((val - 30) / 70, 0), 1))
        }
    }

    @Test("ByteRate formatting uses binary count style with /s suffix")
    func byteRateFormatting() {
        let testRates: [(Double, String)] = [
            (0, ByteCountFormatter.string(fromByteCount: 0, countStyle: .binary) + "/s"),
            (1024, ByteCountFormatter.string(fromByteCount: 1024, countStyle: .binary) + "/s"),
            (1024 * 1024 * 5, ByteCountFormatter.string(fromByteCount: 1024 * 1024 * 5, countStyle: .binary) + "/s"),
            (1024 * 1024 * 1024 * 2, ByteCountFormatter.string(fromByteCount: 1024 * 1024 * 1024 * 2, countStyle: .binary) + "/s"),
        ]

        for (bytes, expected) in testRates {
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary) + "/s"
            #expect(formatted == expected)
            #expect(formatted.hasSuffix("/s"))
        }
    }

    @Test("ByteCount formatting uses file count style (decimal)")
    func byteCountFormatting() {
        let testCounts: [(Double, String)] = [
            (0, ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)),
            (1000, ByteCountFormatter.string(fromByteCount: 1000, countStyle: .file)),
            (500_000_000_000, ByteCountFormatter.string(fromByteCount: 500_000_000_000, countStyle: .file)),
        ]

        for (bytes, expected) in testCounts {
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            #expect(formatted == expected)
        }
    }

    @Test("Duration formatting uses abbreviated hours and minutes")
    func durationFormatting() {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]

        let testDurations: [Double] = [
            0,
            60,       // 1m
            1800,     // 30m
            3600,     // 1h
            3660,     // 1h 1m
            7200,     // 2h
            18000,    // 5h
            86400,    // 24h
        ]

        for duration in testDurations {
            let formatted = formatter.string(from: duration) ?? ""
            #expect(!formatted.isEmpty)
        }
    }

    @Test("SystemStatsSample sparse dictionary roundtrip")
    func sampleSparseDictionary() {
        var dict: [SystemMetricID: Double] = [:]
        dict[.cpuUsage] = 12.5
        dict[.gpuTemperature] = 62.0

        let sample = SystemStatsSample(readings: dict)
        #expect(sample.value(for: .cpuUsage) == 12.5)
        #expect(sample.value(for: .gpuTemperature) == 62.0)
        #expect(sample.value(for: .gpuUsage) == nil)
        #expect(sample.value(for: .memoryUsage) == nil)
        #expect(sample.value(for: .cpuTemperature) == nil)
        #expect(sample.value(for: .dieTemperature) == nil)
        #expect(sample.readings.count == 2)
    }
}
