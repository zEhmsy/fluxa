import Foundation
import Testing
@testable import FluxaCore

@Suite("AlertThreshold")
struct AlertThresholdTests {

    @Test("AlertThreshold initializer defaults")
    func alertThresholdInitDefaults() {
        let threshold = AlertThreshold(
            metricID: .cpuUsage,
            direction: .above,
            limit: 90
        )

        #expect(threshold.metricID == .cpuUsage)
        #expect(threshold.direction == .above)
        #expect(threshold.limit == 90)
        #expect(threshold.isEnabled == true)

        let customID = UUID()
        let customThreshold = AlertThreshold(
            id: customID,
            metricID: .diskFreeSpace,
            direction: .below,
            limit: 1024,
            isEnabled: false
        )
        #expect(customThreshold.id == customID)
        #expect(customThreshold.metricID == .diskFreeSpace)
        #expect(customThreshold.direction == .below)
        #expect(customThreshold.limit == 1024)
        #expect(customThreshold.isEnabled == false)
    }

    @Test("AlertThreshold defaults contain the three expected seed records disabled")
    func alertThresholdDefaults() {
        let defaults = AlertThreshold.defaults
        #expect(defaults.count == 3)

        // 1. CPU usage above 90%
        let cpu = defaults.first { $0.metricID == .cpuUsage }
        #expect(cpu != nil)
        #expect(cpu?.direction == .above)
        #expect(cpu?.limit == 90.0)
        #expect(cpu?.isEnabled == false)

        // 2. Die temperature above 90°C
        let temp = defaults.first { $0.metricID == .dieTemperature }
        #expect(temp != nil)
        #expect(temp?.direction == .above)
        #expect(temp?.limit == 90.0)
        #expect(temp?.isEnabled == false)

        // 3. Free disk space below 5 GB
        let disk = defaults.first { $0.metricID == .diskFreeSpace }
        #expect(disk != nil)
        #expect(disk?.direction == .below)
        #expect(disk?.limit == Double(5 * 1024 * 1024 * 1024))
        #expect(disk?.isEnabled == false)
    }

    @Test("AlertThreshold JSON encoding and decoding roundtrip")
    func alertThresholdCodable() throws {
        let original = [
            AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 85.5, isEnabled: true),
            AlertThreshold(metricID: .diskFreeSpace, direction: .below, limit: 10 * 1024 * 1024 * 1024, isEnabled: false),
            AlertThreshold(metricID: .gpuTemperature, direction: .above, limit: 80, isEnabled: true)
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode([AlertThreshold].self, from: data)

        #expect(decoded == original)
        #expect(decoded.count == original.count)
        for i in 0..<original.count {
            #expect(decoded[i].id == original[i].id)
            #expect(decoded[i].metricID == original[i].metricID)
            #expect(decoded[i].direction == original[i].direction)
            #expect(decoded[i].limit == original[i].limit)
            #expect(decoded[i].isEnabled == original[i].isEnabled)
        }
    }

    @Test("Direction above isCrossed and hasCleared logic")
    func directionAboveCalculations() {
        let direction = AlertThreshold.Direction.above
        let limit = 100.0
        let resetBand = 0.10 // Reset threshold is 100 * (1 - 0.10) = 90.0

        // isCrossed (value >= limit)
        #expect(direction.isCrossed(value: 99.9, limit: limit) == false)
        #expect(direction.isCrossed(value: 100.0, limit: limit) == true)
        #expect(direction.isCrossed(value: 100.1, limit: limit) == true)
        #expect(direction.isCrossed(value: 150.0, limit: limit) == true)

        // hasCleared (value < limit * (1 - resetBand))
        #expect(direction.hasCleared(value: 100.0, limit: limit, resetBand: resetBand) == false)
        #expect(direction.hasCleared(value: 95.0, limit: limit, resetBand: resetBand) == false)
        #expect(direction.hasCleared(value: 90.0, limit: limit, resetBand: resetBand) == false)
        #expect(direction.hasCleared(value: 89.99, limit: limit, resetBand: resetBand) == true)
        #expect(direction.hasCleared(value: 0.0, limit: limit, resetBand: resetBand) == true)
    }

    @Test("Direction below isCrossed and hasCleared logic")
    func directionBelowCalculations() {
        let direction = AlertThreshold.Direction.below
        let limit = 100.0
        let resetBand = 0.10 // Reset threshold is 100 * (1 + 0.10) = 110.0

        // isCrossed (value <= limit)
        #expect(direction.isCrossed(value: 100.1, limit: limit) == false)
        #expect(direction.isCrossed(value: 100.0, limit: limit) == true)
        #expect(direction.isCrossed(value: 99.9, limit: limit) == true)
        #expect(direction.isCrossed(value: 50.0, limit: limit) == true)

        // hasCleared (value > limit * (1 + resetBand))
        #expect(direction.hasCleared(value: 90.0, limit: limit, resetBand: resetBand) == false)
        #expect(direction.hasCleared(value: 100.0, limit: limit, resetBand: resetBand) == false)
        #expect(direction.hasCleared(value: 105.0, limit: limit, resetBand: resetBand) == false)
        #expect(direction.hasCleared(value: 110.0, limit: limit, resetBand: resetBand) == false)
        #expect(direction.hasCleared(value: 110.01, limit: limit, resetBand: resetBand) == true)
        #expect(direction.hasCleared(value: 200.0, limit: limit, resetBand: resetBand) == true)
    }

    @Test("Boundary and extreme values for direction evaluation")
    func extremeValuesEvaluation() {
        let directionAbove = AlertThreshold.Direction.above
        let directionBelow = AlertThreshold.Direction.below

        // Zero limit
        #expect(directionAbove.isCrossed(value: 0, limit: 0) == true)
        #expect(directionAbove.isCrossed(value: -0.1, limit: 0) == false)
        #expect(directionBelow.isCrossed(value: 0, limit: 0) == true)
        #expect(directionBelow.isCrossed(value: 0.1, limit: 0) == false)

        // Large numbers (e.g. disk sizes: 1 TB)
        let oneTB = 1024.0 * 1024.0 * 1024.0 * 1024.0
        #expect(directionBelow.isCrossed(value: oneTB - 1, limit: oneTB) == true)
        #expect(directionBelow.isCrossed(value: oneTB + 1, limit: oneTB) == false)
        #expect(directionBelow.hasCleared(value: oneTB * 1.11, limit: oneTB, resetBand: 0.10) == true)
        #expect(directionBelow.hasCleared(value: oneTB * 1.09, limit: oneTB, resetBand: 0.10) == false)
    }
}
