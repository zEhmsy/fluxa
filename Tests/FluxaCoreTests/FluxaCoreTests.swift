import Testing
import Foundation
@testable import FluxaCore

@Suite("FluxaCore")
struct FluxaCoreTests {
    @Test("SystemMetricID raw values remain stable")
    func systemMetricIDRawValuesRemainStable() {
        #expect(SystemMetricID.cpuUsage.rawValue == "system.cpu")
        #expect(SystemMetricID.gpuUsage.rawValue == "system.gpu")
        #expect(SystemMetricID.memoryUsage.rawValue == "system.memory")
        #expect(SystemMetricID.cpuTemperature.rawValue == "system.cpuTemp")
        #expect(SystemMetricID.gpuTemperature.rawValue == "system.gpuTemp")
        #expect(SystemMetricID.dieTemperature.rawValue == "system.dieTemp")
    }

    @Test("SystemMetricID kind mappings and metadata are correct")
    func systemMetricIDMetadata() {
        #expect(SystemMetricID.cpuUsage.kind == .percentage)
        #expect(SystemMetricID.gpuUsage.kind == .percentage)
        #expect(SystemMetricID.memoryUsage.kind == .percentage)
        #expect(SystemMetricID.cpuTemperature.kind == .temperature)
        #expect(SystemMetricID.gpuTemperature.kind == .temperature)
        #expect(SystemMetricID.dieTemperature.kind == .temperature)

        #expect(SystemMetricID.Kind.percentage.hasBoundedRange == true)
        #expect(SystemMetricID.Kind.temperature.hasBoundedRange == true)
        #expect(SystemMetricID.Kind.byteRate.hasBoundedRange == false)
        #expect(SystemMetricID.Kind.byteCount.hasBoundedRange == false)
        #expect(SystemMetricID.Kind.duration.hasBoundedRange == false)
    }

    @Test("SystemStatsSample is keyed and empty sample contains no readings")
    func emptySystemStatsSampleContainsNoReadings() {
        let sample = SystemStatsSample.empty

        #expect(sample.readings.isEmpty)
        for id in SystemMetricID.allCases {
            #expect(sample.value(for: id) == nil)
        }

        let customSample = SystemStatsSample(readings: [.cpuUsage: 45.0, .memoryUsage: 70.0])
        #expect(customSample.value(for: .cpuUsage) == 45.0)
        #expect(customSample.value(for: .memoryUsage) == 70.0)
        #expect(customSample.value(for: .gpuUsage) == nil)
    }

    @Test("SystemMetric fraction calculation across bounded and unbounded kinds")
    func systemMetricFractionCalculations() {
        // Percentage: 0...100 clamped
        #expect(SystemMetric(id: .cpuUsage, value: -10).fraction == 0.0)
        #expect(SystemMetric(id: .cpuUsage, value: 0).fraction == 0.0)
        #expect(SystemMetric(id: .cpuUsage, value: 50).fraction == 0.5)
        #expect(SystemMetric(id: .cpuUsage, value: 100).fraction == 1.0)
        #expect(SystemMetric(id: .cpuUsage, value: 150).fraction == 1.0)

        // Temperature: 30...100 clamped
        #expect(SystemMetric(id: .cpuTemperature, value: 20).fraction == 0.0)
        #expect(SystemMetric(id: .cpuTemperature, value: 30).fraction == 0.0)
        #expect(SystemMetric(id: .cpuTemperature, value: 65).fraction == 0.5)
        #expect(SystemMetric(id: .cpuTemperature, value: 100).fraction == 1.0)
        #expect(SystemMetric(id: .cpuTemperature, value: 120).fraction == 1.0)
    }

    @Test("SystemMetric severity bands across bounded kinds")
    func systemMetricSeverityBands() {
        // Percentage: <75 normal, <90 warning, >=90 critical
        #expect(SystemMetric(id: .cpuUsage, value: 74.9).severity == .normal)
        #expect(SystemMetric(id: .cpuUsage, value: 75.0).severity == .warning)
        #expect(SystemMetric(id: .cpuUsage, value: 89.9).severity == .warning)
        #expect(SystemMetric(id: .cpuUsage, value: 90.0).severity == .critical)

        // Temperature: <70 normal, <85 warning, >=85 critical
        #expect(SystemMetric(id: .cpuTemperature, value: 69.9).severity == .normal)
        #expect(SystemMetric(id: .cpuTemperature, value: 70.0).severity == .warning)
        #expect(SystemMetric(id: .cpuTemperature, value: 84.9).severity == .warning)
        #expect(SystemMetric(id: .cpuTemperature, value: 85.0).severity == .critical)
    }

    @Test("SystemMetric displayText formats percentage and temperature cleanly")
    func systemMetricDisplayTextFormatting() {
        #expect(SystemMetric(id: .cpuUsage, value: 42.4).displayText == "42%")
        #expect(SystemMetric(id: .cpuUsage, value: 42.6).displayText == "43%")
        #expect(SystemMetric(id: .cpuTemperature, value: 58.2).displayText == "58°")
        #expect(SystemMetric(id: .cpuTemperature, value: 89.7).displayText == "90°")
        #expect(SystemMetric(id: .cpuUsage, value: 42).tooltip == "CPU Usage: 42%")
    }

    @Test("MemorySampler returns a bounded percentage or nil")
    func memorySamplerReturnsBoundedPercentageOrNil() {
        if let value = MemorySampler().sample() {
            #expect((0...100).contains(value))
        }
    }
}

