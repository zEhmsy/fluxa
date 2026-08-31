import Foundation
import Testing
@testable import FluxaCore

@Suite("PeripheralBatterySamplers")
struct PeripheralBatterySamplerTests {

    @Test("PeripheralBatterySampler returns valid readings and excludes internal battery")
    func peripheralBatterySamplerLive() {
        let sampler = PeripheralBatterySampler()
        let peripherals = sampler.sample()

        for device in peripherals {
            #expect((0...100).contains(device.level))
            #expect(!device.name.isEmpty)
            #expect(!device.id.isEmpty)
            // Name should not be internal battery
            #expect(!device.name.localizedCaseInsensitiveContains("InternalBattery"))
        }
    }

    @Test("PeripheralBatteryReading value semantics and equality")
    func peripheralBatteryReadingSemantics() {
        let readingA = PeripheralBatteryReading(
            id: "mouse-123",
            name: "Magic Mouse",
            level: 82,
            isCharging: false
        )
        let readingB = PeripheralBatteryReading(
            id: "mouse-123",
            name: "Magic Mouse",
            level: 82,
            isCharging: false
        )
        let readingC = PeripheralBatteryReading(
            id: "trackpad-456",
            name: "Magic Trackpad",
            level: 95,
            isCharging: true
        )

        #expect(readingA == readingB)
        #expect(readingA != readingC)
        #expect(readingA.id == "mouse-123")
        #expect(readingC.isCharging == true)
    }

    @Test("Benchmark peripheral battery sampling latency")
    func benchmarkPeripheralBatterySampler() {
        let sampler = PeripheralBatterySampler()
        _ = sampler.sample()

        let iterations = 100
        let start = DispatchTime.now().uptimeNanoseconds

        for _ in 0..<iterations {
            _ = sampler.sample()
        }

        let end = DispatchTime.now().uptimeNanoseconds
        let totalNs = end - start
        let perOpMs = Double(totalNs) / Double(iterations) / 1_000_000.0

        // IOPowerSources list traversal is < 1ms, bound at 10ms
        #expect(perOpMs < 10.0)
    }
}
