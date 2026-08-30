import Testing
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

    @Test("SystemStatsSample.empty contains no readings")
    func emptySystemStatsSampleContainsNoReadings() {
        let sample = SystemStatsSample.empty

        #expect(sample.cpuUsage == nil)
        #expect(sample.gpuUsage == nil)
        #expect(sample.memoryUsage == nil)
        #expect(sample.cpuTemperature == nil)
        #expect(sample.gpuTemperature == nil)
        #expect(sample.dieTemperature == nil)
    }

    @Test("MemorySampler returns a bounded percentage or nil")
    func memorySamplerReturnsBoundedPercentageOrNil() {
        if let value = MemorySampler().sample() {
            #expect((0...100).contains(value))
        }
    }
}
