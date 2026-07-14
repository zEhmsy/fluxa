<div align="center">

# ⚡ Fluxa

**Essential macOS system controls, one click away in your menu bar.**

Built entirely in **Swift + SwiftUI** with zero third-party dependencies — just Apple frameworks and clean architecture.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)
[![Release](https://img.shields.io/github/v/release/zEhmsy/fluxa?color=brightgreen)](https://github.com/zEhmsy/fluxa/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/zEhmsy/fluxa/total)](https://github.com/zEhmsy/fluxa/releases)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue)](LICENSE)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)

[**⬇ Download**](https://github.com/zEhmsy/fluxa/releases/latest) · [Features](#-features) · [Install](#-installation) · [Architecture](#-architecture) · [Contributing](#-contributing)

<a href="https://www.buymeacoffee.com/gturturro">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="41" width="174">
</a>

</div>

---

## ✨ Features

Thirteen quick actions, every one backed by a real system API — no fake toggles.

| Action | Type | Description |
|--------|------|-------------|
| ⚡ **Keep Awake** | Toggle + Timer | Prevents display sleep via IOKit power assertion — indefinitely or for 15 min / 1 h / 4 h with auto-off |
| 🌗 **Dark Mode** | Toggle | Switches the system appearance instantly |
| 🖥 **Hide Desktop Icons** | Toggle | Hides/shows Finder desktop icons for clean screenshots & presentations |
| 👁 **Show Hidden Files** | Toggle | Reveals dotfiles in Finder |
| 📥 **Auto-hide Dock** | Toggle | Shows the Dock only on hover |
| 🌙 **Screen Saver** | Button | Launches the system screen saver |
| ✨ **Screen Clean** | Button | Full-screen black overlay on all displays for safe screen wiping |
| ⌨️ **Lock Keyboard** | Toggle | Transparent overlay that intercepts keyboard input (ESC to exit) |
| 🎯 **Focus Mode** | Toggle | Enables/disables Do Not Disturb via user-created Shortcuts |
| 🔊 **Audio Output** | Menu | Switches audio output device with one click, hot-plug aware |
| 🎧 **Bluetooth Audio** | Menu | Connects/disconnects paired AirPods & headphones — no Bluetooth menu digging |
| 🎤 **Microphone Mute** | Toggle | Mutes/unmutes the default input device via CoreAudio |
| 📐 **Lid Angle** | Window | Live MacBook lid angle readout straight from the hinge sensor (Apple Silicon & Intel) |

### Beyond the actions

- **Customizable layout** — reorder, show, or hide actions from the Customize window
- **Per-action color design** — tinted icon tiles that fill when a toggle is active
- **Persistent preferences** — order, visibility, and states survive relaunches
- **Menu bar native** — no Dock icon; template icon adapts to light/dark menu bars
- **Multi-display aware** — Screen Clean and Lock Keyboard cover every connected screen
- **Global shortcut & launch at login** built in

---

## 📦 Installation

### Download (recommended)

Grab **`Fluxa-x.y.z.dmg`** from the [latest release](https://github.com/zEhmsy/fluxa/releases/latest), open it, and drag **Fluxa.app** into **Applications**.

> ⚠️ **Gatekeeper note** — Fluxa is ad-hoc signed (not notarized). On first launch use
> right-click → **Open**, or clear the quarantine flag:
> ```bash
> xattr -cr /Applications/Fluxa.app
> ```

### Build from source

```bash
git clone https://github.com/zEhmsy/fluxa.git
cd fluxa
./build.sh
cp -r Fluxa.app /Applications/
```

The `build.sh` script builds a release binary, assembles a standard `.app` bundle
(including the SwiftPM resource bundle), signs it with entitlements, and prints next steps.

<details>
<summary>Manual build, step by step</summary>

```bash
swift build -c release
codesign --force --sign - --entitlements Fluxa.entitlements .build/release/Fluxa
open .build/release/Fluxa
```

</details>

### Requirements

- **macOS 14 (Sonoma)** or later
- **Xcode Command Line Tools** (building from source only)

---

## 🔐 Permissions

Fluxa asks only for what a feature actually needs, when you first use it:

| Permission | Used by | When |
|-----------|---------|------|
| **Automation (System Events)** | Dark Mode | First toggle — one-time macOS prompt |
| **Bluetooth** | Bluetooth Audio | First connection |
| **Accessibility** *(optional)* | Lock Keyboard | Stricter key interception; works without it too |
| **Shortcuts app** | Focus Mode | One-time guided setup (see below) |

### Focus Mode setup

macOS has no public API to toggle Do Not Disturb, so Fluxa runs two Shortcuts you create once — a guided wizard opens on first use:

1. **Open Shortcuts** from the wizard
2. Create **"Fluxa Focus On"** → action *Set Focus: Turn On*
3. Create **"Fluxa Focus Off"** → action *Set Focus: Turn Off*
4. Tap **Done** — Fluxa remembers the setup

If the shortcuts are ever deleted, Fluxa detects it and re-opens the wizard.

### Sandbox & App Store

Fluxa is **not sandboxed** and cannot ship on the Mac App Store: IOKit assertions,
CoreAudio device control, IOBluetooth, and `defaults`/`killall` all require direct
system access. Built for power users, by design.

---

## 🏗 Architecture

MVVM with a single `@Observable` ViewModel coordinating focused, concrete services — no unnecessary abstractions.

```
Sources/Fluxa/
├── App/
│   ├── FluxaApp.swift               # @main, MenuBarExtra + Window scenes
│   └── AppDelegate.swift            # Cleanup on termination
├── Models/
│   ├── QuickAction.swift            # ActionID, ControlStyle, tints, ActionCatalog
│   └── AppSettings.swift            # @Observable, UserDefaults persistence
├── ViewModels/
│   └── PopoverViewModel.swift       # Central coordinator, owns all services
├── Views/
│   ├── PopoverRootView.swift        # Root container (header, list, bottom bar)
│   ├── ActionListView.swift         # Action list
│   ├── ActionRowView.swift          # Row: toggle / timed toggle / button / menu
│   ├── CustomizeView.swift          # Reorder & visibility editor (own window)
│   ├── BottomBarView.swift          # Customize + Quit
│   ├── FocusOnboardingView.swift    # Focus Mode setup wizard
│   └── LidAngleWindowView.swift     # Animated lid-angle goniometer
├── Services/
│   ├── KeepAwakeService.swift       # IOKit power assertion + expiry timer
│   ├── DarkModeService.swift        # System Events via osascript
│   ├── DesktopIconService.swift     # Finder defaults + killall
│   ├── FinderHiddenFilesService.swift
│   ├── DockAutohideService.swift
│   ├── ScreenSaverService.swift     # NSWorkspace → ScreenSaverEngine
│   ├── ScreenCleanService.swift     # NSPanel overlay (all screens)
│   ├── KeyboardShieldService.swift  # NSPanel + local event monitor
│   ├── FocusModeService.swift       # /usr/bin/shortcuts CLI
│   ├── AudioOutputService.swift     # CoreAudio enumeration & switching
│   ├── MicrophoneMuteService.swift  # CoreAudio input volume control
│   ├── BluetoothAudioService.swift  # IOBluetooth paired-device connect
│   ├── LidAngleMonitor.swift        # HID sensor (Apple Silicon) + IORegistry (Intel)
│   ├── GlobalShortcutService.swift  # Carbon hotkey
│   ├── LaunchAtLoginService.swift   # SMAppService
│   ├── ShellRunner.swift            # Shared Process helper
│   └── FluxaError.swift             # Centralized error types
└── Resources/
    ├── fluxa.icns                   # App icon
    └── Info.plist                   # LSUIElement, permissions text, metadata
```

### Design principles

- **MVVM** — views observe one `@Observable` ViewModel; services are implementation details
- **MainActor isolation** — UI state and services run on the main actor; blocking calls (Bluetooth connect) hop off it
- **Honest UX** — if an API doesn't exist, the app says so instead of faking a toggle
- **Zero dependencies** — SwiftUI, AppKit, IOKit, CoreAudio, IOBluetooth, ApplicationServices. Nothing else.

### API limitations & trade-offs

| Area | Limitation | Workaround |
|------|-----------|------------|
| Focus Mode | No public DND/Focus API | User-created Shortcuts + optimistic local state |
| Dark Mode | No public appearance API | System Events scripting (Automation permission) |
| Keyboard Lock | Full intercept needs Accessibility | Local event monitor fallback covers most keys |
| Lid Angle | Sensor API differs by platform | HID feature report on Apple Silicon, IORegistry on Intel |
| Desktop icons / hidden files | Need a Finder restart | `killall Finder` — brief flicker is expected |
| App Sandbox | Incompatible with the above | Ad-hoc signing; not App Store eligible |

---

## 🛠 Development

```bash
swift build                                  # debug build
swift run Fluxa                              # run directly
swift build -c release                       # release build
swift build -Xswiftc -warnings-as-errors     # what build.sh enforces
```

Regenerate the app icon from code:

```bash
swift generate_icon.swift
cp fluxa.icns Sources/Fluxa/Resources/
```

---

## 🤝 Contributing

Contributions are welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a Pull Request

Found a bug or want an action added? [Open an issue](https://github.com/zEhmsy/fluxa/issues).

---

## ☕ Support

If Fluxa saves you a few clicks every day, you can fuel the next feature:

<a href="https://www.buymeacoffee.com/gturturro">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="41" width="174">
</a>

---

## 📄 License

Licensed under the **Apache License 2.0** — see [LICENSE](LICENSE).

---

<p align="center">
  <sub>Built with Swift and caffeine.</sub>
</p>
