# Fluxa

A lightweight native macOS menu bar utility that puts essential system controls one click away.

Built entirely in **Swift + SwiftUI** with zero third-party dependencies — just Apple frameworks and clean architecture.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-Apache%202.0-blue)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)

---

## Features

| Action | Type | Description |
|--------|------|-------------|
| **Keep Awake** | Toggle | Prevents display sleep using an IOKit power assertion |
| **Hide Desktop Icons** | Toggle | Hides/shows Finder desktop icons instantly |
| **Screen Saver** | Button | Launches the system screen saver |
| **Screen Clean** | Button | Full-screen black overlay on all displays for safe screen wiping |
| **Lock Keyboard** | Toggle | Transparent overlay that intercepts all keyboard input (ESC to exit) |
| **Focus Mode** | Toggle | Enables/disables Do Not Disturb via user-created Shortcuts |
| **Audio Output** | Menu | Switch between audio output devices with one click |

### Additional Capabilities

- **Customizable layout** — Reorder, show, or hide actions from the Customize panel
- **Audio hot-plug detection** — New devices appear automatically when connected
- **Persistent preferences** — Action order, visibility, and toggle states survive relaunches
- **Menu bar native** — No Dock icon; lives entirely in the menu bar with a template icon that adapts to light/dark mode
- **Multi-display aware** — Screen Clean and Lock Keyboard overlays cover all connected screens

---

## Screenshots

<details>
<summary>Popover & Customize Panel</summary>

> *Coming soon — build and try it yourself!*

</details>

---

## Requirements

- **macOS 14 (Sonoma)** or later
- **Xcode Command Line Tools** or full Xcode (for building)
- **Shortcuts app** (pre-installed on macOS) — only needed for Focus Mode

### Optional

- **Accessibility permission** — Grants stricter keyboard blocking in Lock Keyboard mode. The app works without it, but with permission enabled, keyboard events are captured more reliably.

---

## Installation

### Quick Start (Recommended)

```bash
git clone https://github.com/zEhmsy/fluxa.git
cd fluxa
./build.sh
cp -r Fluxa.app /Applications/
```

The `build.sh` script:
1. Builds a release binary
2. Creates a standard macOS `.app` bundle with the icon
3. Signs the bundle with entitlements
4. Prints next steps

Then launch from Applications or use `open Fluxa.app`.

### Manual Build

If you prefer to build step-by-step:

```bash
swift build -c release
codesign --force --sign - --entitlements Fluxa.entitlements .build/release/Fluxa
open .build/release/Fluxa
```

### Sandbox & App Store

Fluxa is **not sandboxed** and cannot be distributed via the Mac App Store. It requires direct access to IOKit, CoreAudio, and shell commands. This is by design — it's built for power users who need privileged system access.

---

## Focus Mode Setup

Focus Mode requires a one-time setup because macOS does not expose a public API to toggle Do Not Disturb programmatically. Fluxa works around this by running user-created Shortcuts.

When you first toggle Focus Mode, Fluxa opens a setup guide:

1. **Open Shortcuts** — tap the button to launch Apple Shortcuts
2. **Create "Fluxa Focus On"** — add a "Set Focus" action set to *Turn On*
3. **Create "Fluxa Focus Off"** — add a "Set Focus" action set to *Turn Off*
4. **Tap Done** — Fluxa remembers the setup is complete

If the shortcuts are ever deleted, Fluxa will detect the failure and re-open the setup guide automatically.

---

## Architecture

```
Sources/Fluxa/
├── App/
│   ├── FluxaApp.swift              # @main, MenuBarExtra + Window scenes
│   └── AppDelegate.swift           # Cleanup on termination
├── Models/
│   ├── QuickAction.swift           # ActionID, ControlStyle, ActionCatalog
│   └── AppSettings.swift           # @Observable, UserDefaults persistence
├── ViewModels/
│   └── PopoverViewModel.swift      # Central coordinator, owns all services
├── Views/
│   ├── PopoverRootView.swift       # Root container (header, list, bottom bar)
│   ├── ActionListView.swift        # Scrollable action list
│   ├── ActionRowView.swift         # Individual row (toggle / button / menu)
│   ├── CustomizeView.swift         # Reorder & visibility editor
│   ├── BottomBarView.swift         # Customize + Quit buttons
│   └── FocusOnboardingView.swift   # Focus Mode setup wizard
├── Services/
│   ├── KeepAwakeService.swift      # IOKit power assertion
│   ├── DesktopIconService.swift    # Finder defaults + killall
│   ├── ScreenSaverService.swift    # NSWorkspace → ScreenSaverEngine
│   ├── ScreenCleanService.swift    # NSPanel overlay (all screens)
│   ├── KeyboardShieldService.swift # NSPanel + local event monitor
│   ├── FocusModeService.swift      # /usr/bin/shortcuts CLI
│   ├── AudioOutputService.swift    # CoreAudio enumeration & switching
│   └── FluxaError.swift            # Centralized error types
└── Resources/
    ├── fluxa.icns                  # App icon (toggle switch design)
    └── Info.plist                  # LSUIElement, bundle metadata
```

### Design Principles

- **MVVM** — Views observe a single `@Observable` ViewModel; services are implementation details
- **Protocol-free simplicity** — No unnecessary abstractions; each service is a focused, concrete type
- **MainActor isolation** — All UI state and services run on the main actor for thread safety
- **Zero dependencies** — Only Apple system frameworks: SwiftUI, IOKit, AppKit, CoreAudio, ApplicationServices

### Frameworks

| Framework | Purpose |
|-----------|---------|
| **SwiftUI** | UI layer, MenuBarExtra, state management |
| **IOKit** | Power management assertions (Keep Awake) |
| **AppKit** | NSPanel overlays, NSWorkspace, NSEvent monitors |
| **CoreAudio** | Audio device enumeration, switching, hot-plug detection |
| **ApplicationServices** | Accessibility API checks (`AXIsProcessTrusted`) |

---

## API Limitations & Trade-offs

| Area | Limitation | Workaround |
|------|-----------|------------|
| Focus Mode | No public API to read or write DND/Focus state | User-created Shortcuts + optimistic local state |
| Keyboard Lock | Full keyboard intercept requires Accessibility permission | Local event monitor as fallback (covers most keys) |
| App Sandbox | Disabled — IOKit, shell commands, and CoreAudio require it | Ad-hoc signing; not App Store eligible |
| Desktop Icons | Requires Finder restart (`killall Finder`) | Brief visual disruption is expected |

---

## Development

```bash
# Debug build
swift build

# Run directly
swift run Fluxa

# Release build
swift build -c release

# Build with warnings as errors (Swift 6 readiness)
swift build -Xswiftc -warnings-as-errors
```

### Generating the App Icon

A utility script is included to regenerate the `.icns` from code:

```bash
swift generate_icon.swift
cp fluxa.icns Sources/Fluxa/Resources/
```

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a Pull Request

---

## License

This project is licensed under the **Apache License 2.0** — see the [LICENSE](LICENSE) file for details.

Apache 2.0 provides:
- Explicit patent grant protection
- Clear trademark guidelines
- Comprehensive liability disclaimers

---

<p align="center">
  <sub>Built with Swift and caffeine.</sub>
</p>
