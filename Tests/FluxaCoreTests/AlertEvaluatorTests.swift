import Foundation
import Testing
@testable import FluxaCore

// MARK: - MockAlertNotifier

private final class MockAlertNotifier: AlertNotifying, @unchecked Sendable {
    struct Record: Equatable {
        let metricID: SystemMetricID
        let value: Double
        let limit: Double
    }

    var records: [Record] = []

    func notify(metricID: SystemMetricID, value: Double, limit: Double) {
        records.append(Record(metricID: metricID, value: value, limit: limit))
    }

    func reset() {
        records.removeAll()
    }
}

// MARK: - AlertEvaluatorTests

@Suite("AlertEvaluator")
struct AlertEvaluatorTests {

    @Test("Disabled threshold never triggers notification")
    @MainActor
    func disabledThresholdNeverTriggers() {
        let mock = MockAlertNotifier()
        let evaluator = AlertEvaluator(notifier: mock)

        let threshold = AlertThreshold(
            metricID: .cpuUsage,
            direction: .above,
            limit: 80.0,
            isEnabled: false
        )

        let sample = SystemStatsSample(readings: [.cpuUsage: 99.0])

        for _ in 0..<100 {
            evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 1.0)
        }

        #expect(mock.records.isEmpty)
        #expect(evaluator.dwellStates.isEmpty)
    }

    @Test("Missing metric reading in sample resets dwell state")
    @MainActor
    func missingMetricReadingResetsDwell() {
        let mock = MockAlertNotifier()
        let evaluator = AlertEvaluator(notifier: mock)

        let threshold = AlertThreshold(
            metricID: .cpuUsage,
            direction: .above,
            limit: 80.0,
            isEnabled: true
        )

        let sampleWithCPU = SystemStatsSample(readings: [.cpuUsage: 95.0])
        let sampleWithoutCPU = SystemStatsSample(readings: [.memoryUsage: 50.0])

        // Hold for 10 samples (at 1s, need 30)
        for _ in 0..<10 {
            evaluator.evaluate(sample: sampleWithCPU, thresholds: [threshold], intervalSeconds: 1.0)
        }
        #expect(evaluator.dwellStates[threshold.id]?.consecutiveHolding == 10)

        // Missing sample resets state
        evaluator.evaluate(sample: sampleWithoutCPU, thresholds: [threshold], intervalSeconds: 1.0)
        #expect(evaluator.dwellStates[threshold.id] == nil)
        #expect(mock.records.isEmpty)
    }

    @Test("Dwell time requirement across various sampling intervals")
    @MainActor
    func dwellTimeCalculationsAcrossIntervals() {
        // 1s interval -> 30s / 1s = 30 samples required
        do {
            let mock = MockAlertNotifier()
            let evaluator = AlertEvaluator(notifier: mock)
            let threshold = AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 90.0, isEnabled: true)
            let sample = SystemStatsSample(readings: [.cpuUsage: 95.0])

            for _ in 1...29 {
                evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 1.0)
            }
            #expect(mock.records.isEmpty)

            // 30th tick fires
            evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 1.0)
            #expect(mock.records.count == 1)
            #expect(mock.records.first == MockAlertNotifier.Record(metricID: .cpuUsage, value: 95.0, limit: 90.0))
        }

        // 5s interval -> 30s / 5s = 6 samples required
        do {
            let mock = MockAlertNotifier()
            let evaluator = AlertEvaluator(notifier: mock)
            let threshold = AlertThreshold(metricID: .dieTemperature, direction: .above, limit: 85.0, isEnabled: true)
            let sample = SystemStatsSample(readings: [.dieTemperature: 90.0])

            for _ in 1...5 {
                evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 5.0)
            }
            #expect(mock.records.isEmpty)

            // 6th tick fires
            evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 5.0)
            #expect(mock.records.count == 1)
            #expect(mock.records.first?.metricID == .dieTemperature)
        }

        // 10s interval -> 30s / 10s = 3 samples required
        do {
            let mock = MockAlertNotifier()
            let evaluator = AlertEvaluator(notifier: mock)
            let threshold = AlertThreshold(metricID: .diskFreeSpace, direction: .below, limit: 5_000_000_000, isEnabled: true)
            let sample = SystemStatsSample(readings: [.diskFreeSpace: 2_000_000_000])

            evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 10.0)
            evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 10.0)
            #expect(mock.records.isEmpty)

            evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 10.0)
            #expect(mock.records.count == 1)
            #expect(mock.records.first?.metricID == .diskFreeSpace)
        }
    }

    @Test("Transient spike does not fire alert and resets consecutive holding count")
    @MainActor
    func transientSpikeDoesNotFire() {
        let mock = MockAlertNotifier()
        let evaluator = AlertEvaluator(notifier: mock)
        let threshold = AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 90.0, isEnabled: true)

        let spikeSample = SystemStatsSample(readings: [.cpuUsage: 99.0])
        let normalSample = SystemStatsSample(readings: [.cpuUsage: 40.0])

        // 10 samples of spike
        for _ in 0..<10 {
            evaluator.evaluate(sample: spikeSample, thresholds: [threshold], intervalSeconds: 1.0)
        }
        #expect(evaluator.dwellStates[threshold.id]?.consecutiveHolding == 10)

        // 1 sample of normal usage resets consecutive count
        evaluator.evaluate(sample: normalSample, thresholds: [threshold], intervalSeconds: 1.0)
        #expect(evaluator.dwellStates[threshold.id]?.consecutiveHolding == 0)

        // Another 15 samples of spike (total consecutive is 15 < 30)
        for _ in 0..<15 {
            evaluator.evaluate(sample: spikeSample, thresholds: [threshold], intervalSeconds: 1.0)
        }
        #expect(evaluator.dwellStates[threshold.id]?.consecutiveHolding == 15)
        #expect(mock.records.isEmpty)
    }

    @Test("Hysteresis prevents spamming and requires retreat past reset band before re-arming")
    @MainActor
    func hysteresisAndRearming() {
        let mock = MockAlertNotifier()
        let evaluator = AlertEvaluator(notifier: mock)
        let threshold = AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 90.0, isEnabled: true)
        // Reset band is 10%: clear threshold is 90 * (1 - 0.10) = 81.0

        let firingSample = SystemStatsSample(readings: [.cpuUsage: 95.0])
        let intermediateSample = SystemStatsSample(readings: [.cpuUsage: 85.0]) // below 90, but above 81
        let clearSample = SystemStatsSample(readings: [.cpuUsage: 75.0]) // below 81

        // Fire once after 30 samples (1s interval)
        for _ in 0..<30 {
            evaluator.evaluate(sample: firingSample, thresholds: [threshold], intervalSeconds: 1.0)
        }
        #expect(mock.records.count == 1)
        #expect(evaluator.dwellStates[threshold.id]?.isCurrentlyFiring == true)

        // 20 more samples at 95%: must not re-fire
        for _ in 0..<20 {
            evaluator.evaluate(sample: firingSample, thresholds: [threshold], intervalSeconds: 1.0)
        }
        #expect(mock.records.count == 1)

        // 10 samples at 85% (not holding, but NOT cleared): isCurrentlyFiring remains true
        for _ in 0..<10 {
            evaluator.evaluate(sample: intermediateSample, thresholds: [threshold], intervalSeconds: 1.0)
        }
        #expect(mock.records.count == 1)
        #expect(evaluator.dwellStates[threshold.id]?.isCurrentlyFiring == true)

        // Another 30 samples at 95% while still not cleared: must not re-fire!
        for _ in 0..<30 {
            evaluator.evaluate(sample: firingSample, thresholds: [threshold], intervalSeconds: 1.0)
        }
        #expect(mock.records.count == 1)

        // 1 sample at 75% clears the reset band
        evaluator.evaluate(sample: clearSample, thresholds: [threshold], intervalSeconds: 1.0)
        #expect(evaluator.dwellStates[threshold.id]?.isCurrentlyFiring == false)

        // Now new episode: 29 samples at 95% -> 0 new notifications
        for _ in 0..<29 {
            evaluator.evaluate(sample: firingSample, thresholds: [threshold], intervalSeconds: 1.0)
        }
        #expect(mock.records.count == 1)

        // 30th sample -> 2nd notification fires!
        evaluator.evaluate(sample: firingSample, thresholds: [threshold], intervalSeconds: 1.0)
        #expect(mock.records.count == 2)
    }

    @Test("Multiple independent thresholds evaluated concurrently")
    @MainActor
    func multipleThresholdsConcurrently() {
        let mock = MockAlertNotifier()
        let evaluator = AlertEvaluator(notifier: mock)

        let cpuThreshold = AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 90.0, isEnabled: true)
        let diskThreshold = AlertThreshold(metricID: .diskFreeSpace, direction: .below, limit: 5_000_000_000, isEnabled: true)
        let tempThreshold = AlertThreshold(metricID: .dieTemperature, direction: .above, limit: 80.0, isEnabled: false) // disabled

        let sample = SystemStatsSample(readings: [
            .cpuUsage: 95.0,
            .diskFreeSpace: 1_000_000_000,
            .dieTemperature: 85.0
        ])

        // 6 samples at 5s interval (dwell 30s)
        for _ in 0..<6 {
            evaluator.evaluate(
                sample: sample,
                thresholds: [cpuThreshold, diskThreshold, tempThreshold],
                intervalSeconds: 5.0
            )
        }

        #expect(mock.records.count == 2)
        #expect(mock.records.contains { $0.metricID == .cpuUsage })
        #expect(mock.records.contains { $0.metricID == .diskFreeSpace })
        #expect(!mock.records.contains { $0.metricID == .dieTemperature })
    }

    @Test("Dynamic sampling interval change mid-evaluation adjusts required samples on next tick")
    @MainActor
    func dynamicIntervalAdjustment() {
        let mock = MockAlertNotifier()
        let evaluator = AlertEvaluator(notifier: mock)
        let threshold = AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 90.0, isEnabled: true)
        let sample = SystemStatsSample(readings: [.cpuUsage: 95.0])

        // 5 samples at 1s interval (required is 30, so not fired yet)
        for _ in 0..<5 {
            evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 1.0)
        }
        #expect(mock.records.isEmpty)
        #expect(evaluator.dwellStates[threshold.id]?.consecutiveHolding == 5)

        // Interval changed to 10s (required is 30 / 10 = 3 samples).
        // On 6th tick, consecutiveHolding becomes 6 >= 3 -> fires immediately!
        evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 10.0)
        #expect(mock.records.count == 1)
    }

    @Test("Zero or negative interval is handled safely without division by zero")
    @MainActor
    func zeroOrNegativeIntervalSafety() {
        let mock = MockAlertNotifier()
        let evaluator = AlertEvaluator(notifier: mock)
        let threshold = AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 90.0, isEnabled: true)
        let sample = SystemStatsSample(readings: [.cpuUsage: 95.0])

        evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: 0)
        evaluator.evaluate(sample: sample, thresholds: [threshold], intervalSeconds: -5.0)

        #expect(mock.records.isEmpty)
    }

    @Test("Benchmark evaluation latency over high sample volume")
    @MainActor
    func benchmarkAlertEvaluation() {
        let mock = MockAlertNotifier()
        let evaluator = AlertEvaluator(notifier: mock)
        let thresholds = [
            AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 90.0, isEnabled: true),
            AlertThreshold(metricID: .gpuUsage, direction: .above, limit: 90.0, isEnabled: true),
            AlertThreshold(metricID: .diskFreeSpace, direction: .below, limit: 5_000_000_000, isEnabled: true),
            AlertThreshold(metricID: .dieTemperature, direction: .above, limit: 90.0, isEnabled: true)
        ]

        let sample = SystemStatsSample(readings: [
            .cpuUsage: 92.0,
            .gpuUsage: 50.0,
            .diskFreeSpace: 10_000_000_000,
            .dieTemperature: 75.0
        ])

        let iterations = 10_000
        let start = DispatchTime.now().uptimeNanoseconds

        for _ in 0..<iterations {
            evaluator.evaluate(sample: sample, thresholds: thresholds, intervalSeconds: 1.0)
        }

        let end = DispatchTime.now().uptimeNanoseconds
        let totalNs = end - start
        let perOpMicroseconds = Double(totalNs) / Double(iterations) / 1_000.0

        // Each evaluation with 4 thresholds should take < 50 microseconds
        #expect(perOpMicroseconds < 50.0)
    }
}
