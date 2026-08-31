import Foundation
import Testing
@testable import FluxaCore

@Suite("BatterySamplers")
struct BatterySamplerTests {

    @Test("BatterySampler returns valid levels and power states or nil on desktop")
    func batterySamplerLive() {
        var sampler = BatterySampler()
        let reading = sampler.sample()

        if let level = reading.level {
            #expect((0.0...100.0).contains(level))
            #expect(level.isFinite)
        }

        if let timeRemaining = reading.timeRemaining {
            // Either -1 (calculating) or positive seconds
            #expect(timeRemaining == -1.0 || timeRemaining > 0.0)
            #expect(timeRemaining.isFinite)
        }

        // On a machine with battery, isOnACPower is boolean; on desktop, it is nil
        if reading.level != nil {
            #expect(reading.isOnACPower != nil)
        } else {
            #expect(reading.timeRemaining == nil)
            #expect(reading.isOnACPower == nil)
        }
    }

    @Test("Battery time remaining duration formatting and calculating sentinel")
    func batteryTimeRemainingFormatting() {
        let calculating = SystemMetric(id: .batteryTimeRemaining, value: -1)
        #expect(calculating.displayText == "Calculating…")
        #expect(calculating.fraction == 0.0)
        #expect(calculating.severity == .normal)

        let calculatingCustom = SystemMetric(id: .batteryTimeRemaining, value: -120)
        #expect(calculatingCustom.displayText == "Calculating…")

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]

        let twoHours = SystemMetric(id: .batteryTimeRemaining, value: 7200)
        #expect(twoHours.displayText == (formatter.string(from: 7200) ?? ""))
        #expect(twoHours.fraction == 0.0)
        #expect(twoHours.severity == .normal)

        let twoHoursTwoMinutes = SystemMetric(id: .batteryTimeRemaining, value: 7320)
        #expect(twoHoursTwoMinutes.displayText == (formatter.string(from: 7320) ?? ""))
    }

    @Test("Battery level metric formatting and properties")
    func batteryLevelFormatting() {
        let normal = SystemMetric(id: .batteryLevel, value: 50.0)
        #expect(normal.displayText == "50%")
        #expect(normal.fraction == 0.5)
        #expect(normal.severity == .normal)
        #expect(normal.tooltip == "Battery: 50%")

        let high = SystemMetric(id: .batteryLevel, value: 85.0)
        #expect(high.displayText == "85%")
        #expect(high.fraction == 0.85)
        #expect(high.severity == .warning)

        let critical = SystemMetric(id: .batteryLevel, value: 95.0)
        #expect(critical.displayText == "95%")
        #expect(critical.fraction == 0.95)
        #expect(critical.severity == .critical)
    }

    @Test("SystemStatsSampler incorporates battery readings into sample")
    func systemStatsSamplerIncludesBattery() async {
        let sampler = SystemStatsSampler()
        let sample = await sampler.sample()

        if let level = sample.value(for: .batteryLevel) {
            #expect((0.0...100.0).contains(level))
            #expect(sample.isOnACPower != nil)
        }
    }

    @Test("Benchmark battery sampling latency")
    func benchmarkBatterySampler() {
        var sampler = BatterySampler()
        _ = sampler.sample()

        let iterations = 100
        let start = DispatchTime.now().uptimeNanoseconds

        for _ in 0..<iterations {
            _ = sampler.sample()
        }

        let end = DispatchTime.now().uptimeNanoseconds
        let totalNs = end - start
        let perOpMs = Double(totalNs) / Double(iterations) / 1_000_000.0

        // IOPowerSources query is fast (< 1ms per call)
        #expect(perOpMs < 10.0)
    }
}
