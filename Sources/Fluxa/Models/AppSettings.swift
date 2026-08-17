import Foundation
import Observation

// MARK: - AppSettings

/// Persisted user preferences for Fluxa.
/// Uses @Observable for SwiftUI reactivity; writes through to UserDefaults on every mutation.
@Observable
@MainActor
final class AppSettings {

    // MARK: - Persisted Properties

    /// The display order of action IDs. Drives the list order in the popover.
    var actionOrder: [ActionID] {
        didSet { save(actionOrder.map(\.rawValue), forKey: Keys.actionOrder) }
    }

    /// IDs of actions that the user has hidden from the popover.
    var hiddenActionIDs: Set<ActionID> {
        didSet { save(Array(hiddenActionIDs).map(\.rawValue), forKey: Keys.hiddenActionIDs) }
    }

    /// Whether subtitle text is shown under each action title.
    var showSubtitles: Bool {
        didSet { UserDefaults.standard.set(showSubtitles, forKey: Keys.showSubtitles) }
    }

    /// Whether the user has completed the Focus Mode onboarding (created the two Shortcuts).
    var focusModeOnboardingComplete: Bool {
        didSet { UserDefaults.standard.set(focusModeOnboardingComplete, forKey: Keys.focusModeOnboardingComplete) }
    }

    /// Optimistic local state for the Focus Mode toggle.
    /// Tracked locally since no public API can read the real system Focus state.
    var focusModeEnabled: Bool {
        didSet { UserDefaults.standard.set(focusModeEnabled, forKey: Keys.focusModeEnabled) }
    }

    /// Agent quota metrics pinned to the usage strip under the popover header, as
    /// "provider.resource" ids in display order. Empty = the strip is hidden, which is what an
    /// install without OpenUsage (or without a choice made) gets.
    var usageMetricIDs: [String] {
        didSet { save(usageMetricIDs, forKey: Keys.usageMetricIDs) }
    }

    /// How many chips fit the 304pt popover before the percentages stop being readable.
    static let maxUsageMetrics = 3

    /// How often agent quotas are re-read in the background.
    var usageRefreshInterval: UsageRefreshInterval {
        didSet { UserDefaults.standard.set(usageRefreshInterval.rawValue, forKey: Keys.usageRefreshInterval) }
    }

    /// Preferred display unit for the trackpad scale readout.
    var trackpadScaleUnit: WeightUnit {
        didSet { UserDefaults.standard.set(trackpadScaleUnit.rawValue, forKey: Keys.trackpadScaleUnit) }
    }

    // MARK: - Computed

    /// Actions in display order, excluding hidden ones, with resolved QuickAction metadata.
    var visibleActions: [QuickAction] {
        actionOrder
            .filter { !hiddenActionIDs.contains($0) }
            .compactMap { ActionCatalog.action(for: $0) }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard

        // Action order: load from defaults or fall back to enum declaration order
        if let saved = defaults.array(forKey: Keys.actionOrder) as? [String] {
            let decoded = saved.compactMap { ActionID(rawValue: $0) }
            // Merge: keep saved order but append any new IDs added since last launch
            let savedSet = Set(decoded)
            let missing = ActionID.allCases.filter { !savedSet.contains($0) }
            actionOrder = decoded + missing
        } else {
            actionOrder = ActionID.allCases
        }

        // Hidden IDs
        if let saved = defaults.array(forKey: Keys.hiddenActionIDs) as? [String] {
            hiddenActionIDs = Set(saved.compactMap { ActionID(rawValue: $0) })
        } else {
            hiddenActionIDs = []
        }

        // Show subtitles: default true
        showSubtitles = defaults.object(forKey: Keys.showSubtitles) as? Bool ?? true

        // Focus Mode
        focusModeOnboardingComplete = defaults.bool(forKey: Keys.focusModeOnboardingComplete)
        focusModeEnabled = defaults.bool(forKey: Keys.focusModeEnabled)

        // Usage strip: default to Claude's session window on first run. It resolves to nothing —
        // and the strip stays hidden — on a Mac without OpenUsage or without Claude configured,
        // so the default can't add height to a popover that has no data to put there.
        usageMetricIDs = defaults.array(forKey: Keys.usageMetricIDs) as? [String] ?? ["claude.session"]
        usageRefreshInterval = defaults.string(forKey: Keys.usageRefreshInterval)
            .flatMap(UsageRefreshInterval.init(rawValue:)) ?? .fallback

        // Trackpad scale: the hardware reports grams directly, so only the unit is stored
        trackpadScaleUnit = (defaults.string(forKey: Keys.trackpadScaleUnit))
            .flatMap(WeightUnit.init(rawValue:)) ?? .grams
    }

    // MARK: - Private

    private enum Keys {
        static let actionOrder = "fluxa.actionOrder"
        static let hiddenActionIDs = "fluxa.hiddenActionIDs"
        static let showSubtitles = "fluxa.showSubtitles"
        static let focusModeOnboardingComplete = "fluxa.focusModeOnboardingComplete"
        static let focusModeEnabled = "fluxa.focusModeEnabled"
        static let trackpadScaleUnit = "fluxa.trackpadScaleUnit"
        static let usageMetricIDs = "fluxa.usageMetricIDs"
        static let usageRefreshInterval = "fluxa.usageRefreshInterval"
    }

    private func save(_ value: [String], forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
