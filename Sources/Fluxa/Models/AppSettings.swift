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

    /// Main popover appearance. Classic preserves the existing adaptive interface; the Control
    /// Deck variants intentionally use fixed light and dark palettes.
    var visualStyle: FluxaVisualStyle {
        didSet { UserDefaults.standard.set(visualStyle.rawValue, forKey: Keys.visualStyle) }
    }

    /// Records only that the welcome was offered, not that any system permission was granted.
    var hasPresentedPermissionsSetup: Bool {
        didSet { UserDefaults.standard.set(hasPresentedPermissionsSetup, forKey: Keys.permissionsSetup) }
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

    /// Agent quota metrics shown in the menu bar itself. Independent of `usageMetricIDs`: a reading
    /// worth a chip in the popover isn't necessarily worth permanent width in the menu bar.
    var usageMenuBarMetricIDs: [String] {
        didSet { save(usageMenuBarMetricIDs, forKey: Keys.usageMenuBarMetricIDs) }
    }

    /// System readings shown in the popover strip, as `SystemMetricID` raw values in display order.
    var systemMetricIDs: [String] {
        didSet { save(systemMetricIDs, forKey: Keys.systemMetricIDs) }
    }

    /// System readings shown in the menu bar.
    var systemMenuBarMetricIDs: [String] {
        didSet { save(systemMenuBarMetricIDs, forKey: Keys.systemMenuBarMetricIDs) }
    }

    /// How many chips fit the compact popover before the percentages stop being readable.
    static let maxUsageMetrics = 3

    /// How many system chips fit the popover strip on one row.
    static let maxSystemMetrics = 3

    /// How many readings — system and agent together — may occupy the menu bar. One shared budget,
    /// because they compete for the same finite strip of width next to everyone else's icons.
    static let maxMenuBarMetrics = 4

    /// How many menu bar slots are already taken, so Customize can grey out what won't fit.
    var menuBarMetricCount: Int {
        systemMenuBarMetricIDs.count + usageMenuBarMetricIDs.count
    }

    /// How often agent quotas are re-read in the background.
    var usageRefreshInterval: UsageRefreshInterval {
        didSet { UserDefaults.standard.set(usageRefreshInterval.rawValue, forKey: Keys.usageRefreshInterval) }
    }

    /// How often CPU/GPU/memory/temperature are re-sampled.
    var systemStatsInterval: SystemStatsInterval {
        didSet { UserDefaults.standard.set(systemStatsInterval.rawValue, forKey: Keys.systemStatsInterval) }
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

        // Existing installs have no stored value and must retain the interface they already know.
        visualStyle = defaults.string(forKey: Keys.visualStyle)
            .flatMap(FluxaVisualStyle.init(rawValue:)) ?? .classic
        hasPresentedPermissionsSetup = defaults.bool(forKey: Keys.permissionsSetup)

        // Focus Mode
        focusModeOnboardingComplete = defaults.bool(forKey: Keys.focusModeOnboardingComplete)
        focusModeEnabled = defaults.bool(forKey: Keys.focusModeEnabled)

        // Usage strip: default to Claude's session window on first run. It resolves to nothing —
        // and the strip stays hidden — on a Mac without OpenUsage or without Claude configured,
        // so the default can't add height to a popover that has no data to put there.
        let pinnedUsageIDs = defaults.array(forKey: Keys.usageMetricIDs) as? [String] ?? ["claude.session"]
        usageMetricIDs = pinnedUsageIDs
        usageRefreshInterval = defaults.string(forKey: Keys.usageRefreshInterval)
            .flatMap(UsageRefreshInterval.init(rawValue:)) ?? .fallback

        // Menu bar visibility used to be implied by the popover selection. On the first launch after
        // the split, seed it from that selection so an existing install's menu bar looks exactly as
        // it did before the upgrade; a fresh install starts from the same default for the same
        // reason the popover does.
        if let stored = defaults.array(forKey: Keys.usageMenuBarMetricIDs) as? [String] {
            usageMenuBarMetricIDs = stored
        } else {
            usageMenuBarMetricIDs = pinnedUsageIDs
            // Written through immediately: `didSet` doesn't fire during init, and without this the
            // seed would be recomputed every launch — so later emptying the popover selection would
            // silently empty the menu bar too, long after the migration was supposed to be over.
            defaults.set(pinnedUsageIDs, forKey: Keys.usageMenuBarMetricIDs)
        }

        // System stats: nothing selected by default. The readings are new, and silently adding
        // width to everyone's menu bar (or height to their popover) on upgrade would be a surprise.
        systemMetricIDs = defaults.array(forKey: Keys.systemMetricIDs) as? [String] ?? []
        systemMenuBarMetricIDs = defaults.array(forKey: Keys.systemMenuBarMetricIDs) as? [String] ?? []
        systemStatsInterval = defaults.string(forKey: Keys.systemStatsInterval)
            .flatMap(SystemStatsInterval.init(rawValue:)) ?? .fallback

        // Trackpad scale: the hardware reports grams directly, so only the unit is stored
        trackpadScaleUnit = (defaults.string(forKey: Keys.trackpadScaleUnit))
            .flatMap(WeightUnit.init(rawValue:)) ?? .grams
    }

    // MARK: - Private

    private enum Keys {
        static let actionOrder = "fluxa.actionOrder"
        static let hiddenActionIDs = "fluxa.hiddenActionIDs"
        static let showSubtitles = "fluxa.showSubtitles"
        static let visualStyle = "fluxa.visualStyle"
        static let permissionsSetup = "fluxa.hasPresentedPermissionsSetup"
        static let focusModeOnboardingComplete = "fluxa.focusModeOnboardingComplete"
        static let focusModeEnabled = "fluxa.focusModeEnabled"
        static let trackpadScaleUnit = "fluxa.trackpadScaleUnit"
        static let usageMetricIDs = "fluxa.usageMetricIDs"
        static let usageMenuBarMetricIDs = "fluxa.usageMenuBarMetricIDs"
        static let usageRefreshInterval = "fluxa.usageRefreshInterval"
        static let systemMetricIDs = "fluxa.systemMetricIDs"
        static let systemMenuBarMetricIDs = "fluxa.systemMenuBarMetricIDs"
        static let systemStatsInterval = "fluxa.systemStatsInterval"
    }

    private func save(_ value: [String], forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
