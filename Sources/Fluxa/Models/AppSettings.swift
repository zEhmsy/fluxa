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
    }

    // MARK: - Private

    private enum Keys {
        static let actionOrder = "fluxa.actionOrder"
        static let hiddenActionIDs = "fluxa.hiddenActionIDs"
        static let showSubtitles = "fluxa.showSubtitles"
        static let focusModeOnboardingComplete = "fluxa.focusModeOnboardingComplete"
        static let focusModeEnabled = "fluxa.focusModeEnabled"
    }

    private func save(_ value: [String], forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
