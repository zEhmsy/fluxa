import Foundation
import SwiftUI

// MARK: - FluxaVisualStyle

/// Visual composition used by the main menu-bar dashboard.
///
/// Classic deliberately remains the default so an update never replaces an existing user's
/// interface without consent. The two Control Deck variants share one layout and differ only in
/// their fixed light or dark palette.
enum FluxaVisualStyle: String, CaseIterable, Identifiable, Codable {
    case classic
    case classicLight
    case classicDark
    case cyber
    case cyberDark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:      return "Auto"
        case .classicLight: return "Classic"
        case .classicDark:  return "Classic Dark"
        case .cyber:        return "Cyber"
        case .cyberDark:    return "Cyber Dark"
        }
    }

    /// Whether this style uses the Control Deck layout rather than Classic layout.
    var isCyber: Bool {
        self == .cyber || self == .cyberDark
    }

    /// Whether this style uses the Classic popover layout.
    var isClassic: Bool {
        !isCyber
    }
}

// MARK: - Visual Style Environment

/// Window scenes are separate SwiftUI roots, so the selected presentation is forwarded through a
/// value environment rather than making reusable visual components depend on the settings object.
private struct FluxaVisualStyleEnvironmentKey: EnvironmentKey {
    static let defaultValue = FluxaVisualStyle.classic
}

extension EnvironmentValues {
    var fluxaVisualStyle: FluxaVisualStyle {
        get { self[FluxaVisualStyleEnvironmentKey.self] }
        set { self[FluxaVisualStyleEnvironmentKey.self] = newValue }
    }
}
