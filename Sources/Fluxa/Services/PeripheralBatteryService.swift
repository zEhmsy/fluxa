import Foundation
import FluxaCore
import Observation

// MARK: - PeripheralBatteryService

/// Publishes connected accessory batteries without flickering on a single missing sample.
@Observable
@MainActor
final class PeripheralBatteryService {

    // MARK: - Observable State

    private(set) var devices: [PeripheralBatteryReading] = []

    // MARK: - Private

    private static let missingThreshold = 2
    private static let refreshInterval: Duration = .seconds(60)

    private let sampler = PeripheralBatterySampler()
    private var missingStreak: [String: Int] = [:]
    private var loopTask: Task<Void, Never>?

    // MARK: - Public API

    /// Re-reads accessories, retaining a missing device until a second consecutive miss.
    func refresh() {
        let current = sampler.sample()
        let currentByID = Dictionary(
            current.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        for id in Array(missingStreak.keys) where currentByID[id] == nil {
            missingStreak[id, default: 0] += 1
        }
        for id in currentByID.keys {
            missingStreak[id] = 0
        }

        let retained = devices.filter { device in
            currentByID[device.id] == nil
                && (missingStreak[device.id] ?? Self.missingThreshold) < Self.missingThreshold
        }

        var merged = currentByID
        for device in retained {
            merged[device.id] = device
        }
        missingStreak = missingStreak.filter { $0.value < Self.missingThreshold }

        let sorted = merged.values.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
        if devices != sorted {
            devices = sorted
        }
    }

    /// Starts the fixed background cadence. The caller performs the initial/on-open refresh.
    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }
}
