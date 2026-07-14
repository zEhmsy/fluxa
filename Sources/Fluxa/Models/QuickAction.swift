import SwiftUI

// MARK: - ActionID

/// Typed identifier for each quick action. String rawValue enables UserDefaults persistence
/// and automatic forward/backward migration (unknown values are silently dropped by compactMap).
enum ActionID: String, CaseIterable, Codable, Identifiable {
    case keepAwake
    case darkMode     // System appearance toggle via System Events (osascript)
    case desktopIcons
    case hiddenFiles  // Finder AppleShowAllFiles toggle
    case dockAutohide // Dock autohide toggle
    case screenSaver
    case screenClean
    case lockKeyboard
    case focusMode    // Opens System Settings → Focus (no public toggle API on macOS 13+)
    case audioOutput  // CoreAudio output device switcher
    case bluetoothAudio // IOBluetooth quick-connect for AirPods/headphones
    case micMute      // CoreAudio input volume control (mute/unmute default input device)
    case lidAngle     // IORegistry lid angle monitor (MacBook only)

    var id: String { rawValue }
}

// MARK: - QuickAction

/// Pure display model for a single action row. Contains no business logic or service references.
struct QuickAction: Identifiable {
    let id: ActionID
    let title: String
    /// Static subtitle shown when no dynamic override is available.
    let subtitle: String?
    /// SF Symbol name for the leading icon (inactive / default state).
    let icon: String
    /// SF Symbol name shown when the action is active (toggle ON). Nil = always use `icon`.
    let activeIcon: String?
    /// Accent color for the icon tile (and its filled background when active).
    let tint: Color
    /// Determines which trailing control is rendered in the row.
    let controlStyle: ControlStyle

    enum ControlStyle: Equatable {
        /// A boolean toggle (on/off state managed by ViewModel).
        case toggle
        /// A toggle plus a timer menu for timed activation (Keep Awake).
        case timedToggle
        /// A one-shot trigger button — no persistent on/off state.
        case momentaryButton(label: String)
        /// An inline SwiftUI Menu for multi-value selection (e.g. audio device picker).
        case menu
        /// Feature is unavailable; row is greyed with a tooltip explaining why.
        case unavailable(reason: String)
    }
}

// MARK: - ActionCatalog

/// The canonical list of all Fluxa quick actions with their static display metadata.
/// Declaration order defines the default display order in the popover.
enum ActionCatalog {
    static let all: [QuickAction] = [
        QuickAction(
            id: .keepAwake,
            title: "Keep Awake",
            subtitle: "Prevent display sleep indefinitely",
            icon: "bolt",
            activeIcon: "bolt.fill",
            tint: .orange,
            controlStyle: .timedToggle
        ),
        QuickAction(
            id: .darkMode,
            title: "Dark Mode",
            subtitle: "Toggle system appearance",
            icon: "circle.lefthalf.filled",
            activeIcon: nil,
            tint: .yellow,
            controlStyle: .toggle
        ),
        QuickAction(
            id: .desktopIcons,
            title: "Hide Desktop Icons",
            subtitle: "Toggles Finder desktop visibility",
            icon: "desktopcomputer",
            activeIcon: "desktopcomputer.slash",
            tint: .teal,
            controlStyle: .toggle
        ),
        QuickAction(
            id: .hiddenFiles,
            title: "Show Hidden Files",
            subtitle: "Reveal dotfiles in Finder",
            icon: "eye.slash",
            activeIcon: "eye",
            tint: .mint,
            controlStyle: .toggle
        ),
        QuickAction(
            id: .dockAutohide,
            title: "Auto-hide Dock",
            subtitle: "Show the Dock only on hover",
            icon: "dock.rectangle",
            activeIcon: "dock.arrow.down.rectangle",
            tint: .brown,
            controlStyle: .toggle
        ),
        QuickAction(
            id: .screenSaver,
            title: "Screen Saver",
            subtitle: "Launch system screensaver now",
            icon: "moon.stars",
            activeIcon: nil,
            tint: .purple,
            controlStyle: .momentaryButton(label: "Launch")
        ),
        QuickAction(
            id: .screenClean,
            title: "Screen Clean",
            subtitle: "Black overlay for screen cleaning",
            icon: "sparkles",
            activeIcon: nil,
            tint: .cyan,
            controlStyle: .momentaryButton(label: "Activate")
        ),
        QuickAction(
            id: .lockKeyboard,
            title: "Lock Keyboard",
            subtitle: "Overlay shield — ESC or click to exit",
            icon: "keyboard",
            activeIcon: nil,
            tint: .red,
            controlStyle: .toggle
        ),
        QuickAction(
            id: .focusMode,
            title: "Focus Mode",
            // Activated via user-created Shortcuts ("Fluxa Focus On" / "Fluxa Focus Off").
            // State is tracked optimistically in AppSettings — no public API to read true system state.
            // Onboarding guides the user to create the two shortcuts once.
            subtitle: "Via Shortcuts — setup required",
            icon: "moon",
            activeIcon: "moon.fill",
            tint: .indigo,
            controlStyle: .toggle
        ),
        QuickAction(
            id: .audioOutput,
            title: "Audio Output",
            // The subtitle is overridden at runtime by PopoverViewModel.dynamicSubtitle(for:)
            // to show the current output device name (e.g. "MacBook Pro Speakers", "AirPods").
            subtitle: "Select output device",
            icon: "speaker.wave.2",
            activeIcon: nil,
            tint: .blue,
            controlStyle: .menu
        ),
        QuickAction(
            id: .bluetoothAudio,
            title: "Bluetooth Audio",
            // The subtitle is overridden at runtime to show the connected device.
            subtitle: "Connect AirPods & headphones",
            icon: "airpods",
            activeIcon: nil,
            tint: .cyan,
            controlStyle: .menu
        ),
        QuickAction(
            id: .micMute,
            title: "Microphone Mute",
            // The subtitle is overridden at runtime by PopoverViewModel.dynamicSubtitle(for:)
            // to show the current input device name.
            subtitle: "Mute/unmute the default input device",
            // toggle OFF = mic active → mic.fill; toggle ON = muted → mic.slash.fill
            icon: "mic.fill",
            activeIcon: "mic.slash.fill",
            tint: .pink,
            controlStyle: .toggle
        ),
        QuickAction(
            id: .lidAngle,
            title: "Lid Angle",
            subtitle: "MacBook display angle monitor",
            icon: "gyroscope",
            activeIcon: nil,
            tint: .green,
            controlStyle: .momentaryButton(label: "Open")
        ),
    ]

    /// Returns the QuickAction for a given ID, or nil if not found.
    static func action(for id: ActionID) -> QuickAction? {
        all.first { $0.id == id }
    }
}
