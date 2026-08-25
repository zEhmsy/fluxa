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

## 🖼 Interface

<p align="center">
  <img src="docs/images/fluxa-menu.png" alt="Fluxa menu-bar panel" width="328">
  &nbsp;&nbsp;
  <img src="docs/images/fluxa-customize.png" alt="Fluxa in-panel Customize screen" width="328">
</p>

<p align="center"><sub>The main panel and Customize share one fluid menu-bar surface — no focus loss and no separate settings window.</sub></p>

<p align="center">
  <img src="docs/images/fluxa-system-dashboard.png" alt="Fluxa System Dashboard with CPU, GPU, memory, and temperature charts" width="640">
</p>

<p align="center"><sub>Live hardware readings expand into a rolling 30-minute dashboard with separate percentage and temperature scales.</sub></p>

<p align="center">
  <img src="docs/images/fluxa-lid-angle.png" alt="Fluxa Lid Angle window" width="390">
  &nbsp;&nbsp;
  <img src="docs/images/fluxa-trackpad-scale.png" alt="Fluxa Trackpad Scale window" width="400">
</p>

<p align="center"><sub>Hardware tools open as focused, purpose-built windows with the same adaptive visual system.</sub></p>

---

## ✨ Features

Fifteen quick actions, every one backed by a real system API — no fake toggles.

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
| ⚖️ **Trackpad Scale** | Window | Weighs small objects on the Force Touch trackpad's strain gauges |
| 📊 **Agent Usage** | Strip + Window | Live Claude & Codex quota percentages in the menu bar, with usage charts |

### Beyond the actions

- **Customizable layout** — reorder, show, or hide actions without leaving the menu-bar panel
- **Focus-safe navigation** — Customize transitions in place while hardware tools reliably come to the foreground
- **Adaptive high-contrast UI** — shared surfaces, borders, semantic accents, and controls tuned for light and dark appearances
- **Per-action color design** — tinted icon tiles that fill when a toggle is active
- **Persistent preferences** — order, visibility, and states survive relaunches
- **Menu bar native** — no Dock icon; template icon adapts to light/dark menu bars
- **Multi-display aware** — Screen Clean and Lock Keyboard cover every connected screen
- **Global shortcut & launch at login** built in

---

## 🖥 System dashboard

Fluxa can pin live hardware readings in the popover, in the menu bar, or in both places:

- **CPU, GPU and memory usage** — local system counters shown as percentages
- **Temperature** — CPU/GPU readings when the Mac labels sensors per component, otherwise one honest whole-die reading
- **Independent destinations** — up to three readings in the popover and four total system/agent readings in the menu bar
- **Live history window** — click the system strip for separate load and temperature charts covering the latest 30 minutes
- **In-memory by design** — chart history starts when Fluxa launches and is never written to disk
- **Configurable sampling** — 1, 2, 5 or 10 seconds; the dashboard uses the same loop and never doubles the sensor work

CPU, GPU and memory share a fixed 0–100% chart. Temperature uses a separate degree axis so neither
unit is visually compressed. A failed sensor pass creates a gap in the history instead of repeating
an old value as though it had been measured again.

---

## 📊 Agent usage

Fluxa reads how much of your AI coding agents' quota you've burned and keeps it in the menu bar.

```
 ⏻  ✳ 74%   19%          ← the switch mark, then one reading per pinned agent
```

- **Menu bar strip** — each selected agent's mark and percentage, rendered as one template image so it tints itself for light and dark menu bars
- **Popover strip** — the same readings with severity colors (blue → amber at 75% → red at 90%) and a meter per window
- **Charts window** — click the strip: live quota meters plus a GitHub-style contribution grid of tokens spent per day
- **Configurable in Customize** — pick up to three quota windows and the refresh interval

### Where the numbers come from

Two different sources, because they answer different questions.

**Live quotas** come from each agent's own usage endpoint — the same ones its CLI calls:

| Agent | Endpoint | Credentials |
|-------|----------|-------------|
| Claude | `GET api.anthropic.com/api/oauth/usage` | `~/.claude/.credentials.json`, else the `Claude Code-credentials` keychain item |
| Codex | `GET chatgpt.com/backend-api/wham/usage` | `~/.codex/auth.json` |

**Fluxa never refreshes or rewrites those credentials.** Both providers rotate the refresh token when it's used, so renewing one here would invalidate the token Claude Code or Codex is holding — breaking the very login being read. An expired token is reported as expired; running the agent once mints a fresh one.

**Historical charts** come from the agents' own session logs (`~/.claude/projects/**/*.jsonl`, `~/.codex/sessions/**/*.jsonl`), which already hold exact per-turn token counts going back weeks. That's why the grid is populated the first time you open it instead of slowly filling from the day you enable it.

Aggregation details that matter for correctness:

- Days are bucketed by **local** calendar day, not UTC — bucketing by UTC moves an evening's work to the next day for anyone east of Greenwich
- Claude turns are de-duplicated on `message.id`: resumed sessions and sidechains replay the same turn into the log
- Codex `token_count` events whose cumulative total hasn't moved are re-emitted stale snapshots, not new work, and are skipped

Scanning is cached per file in `~/Library/Application Support/Fluxa/`. Session logs are append-only, so a file whose size and modification date are unchanged is never re-read — only the sessions being written right now.

### Privacy

Everything stays on your Mac. Fluxa talks to the agents' usage endpoints and to nothing else — no analytics, no telemetry, no server of its own. Token counts, the scan cache, and your preferences live in `~/Library/Application Support/Fluxa/` and `UserDefaults`, never in the repository or a release artifact.

### Refresh interval

The choices are derived from what the data can express, not round numbers. A 5-hour session window spends 100 percentage points over 300 minutes, so at a steady burn **one percentage point takes three minutes** — polling faster cannot return a different integer, it only spends requests.

| Setting | Movement between reads |
|---------|------------------------|
| Only when opened | Menu bar can lag behind |
| Every 3 minutes | The fastest that can show a new number |
| Every 5 minutes *(default)* | ≈1.7% of a session window |
| Every 15 / 30 minutes | ≈5% / ≈10% of a session window |
| Every hour | Fine for weekly limits, coarse for a session |

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
| **Keychain** | Agent Usage (Claude) | First read of the `Claude Code-credentials` item — choose *Always Allow* |
| **Network** | Agent Usage | Requests to the agents' usage endpoints only |

> **Keychain prompt returns after every rebuild.** macOS ties the "Always Allow" grant to the app's
> code signature, and `build.sh` signs ad-hoc, so each build is a new app as far as the keychain is
> concerned. Signing with a stable Apple Development identity (free with Xcode) makes it stick:
> ```bash
> CODESIGN_IDENTITY="Apple Development: you@example.com" ./build.sh
> ```

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
│   ├── FluxaApp.swift               # @main, MenuBarExtra + focused Window scenes
│   ├── FluxaWindowPresenter.swift   # Window registration + foreground activation
│   └── AppDelegate.swift            # Cleanup on termination
├── Models/
│   ├── QuickAction.swift            # ActionID, ControlStyle, tints, ActionCatalog
│   ├── AppSettings.swift            # @Observable, UserDefaults persistence
│   ├── AgentUsage.swift             # AgentUsageMetric: one agent quota window
│   ├── UsageRefreshInterval.swift   # Agent poll intervals derived from window size
│   ├── SystemMetric.swift           # System metric identity, value and severity
│   ├── SystemStatsHistory.swift      # Sparse timestamped samples for charts
│   └── SystemStatsInterval.swift     # Local sampling intervals
├── ViewModels/
│   └── PopoverViewModel.swift       # Central coordinator, owns all services
├── Views/
│   ├── PopoverRootView.swift        # Root container (header, list, bottom bar)
│   ├── FluxaTheme.swift             # Adaptive palette + shared UI components
│   ├── ActionListView.swift         # Action list
│   ├── ActionRowView.swift          # Row: toggle / timed toggle / button / menu
│   ├── CustomizeView.swift          # In-panel reorder & visibility editor
│   ├── BottomBarView.swift          # Customize + Quit
│   ├── FocusOnboardingView.swift    # Focus Mode setup wizard
│   ├── LidAngleWindowView.swift     # Animated lid-angle goniometer
│   ├── TrackpadScaleWindowView.swift# Force Touch scale readout
│   ├── SystemStatsStripView.swift    # Live hardware strip under the header
│   ├── SystemStatsWindowView.swift   # 30-minute load + temperature charts
│   ├── AgentUsageStripView.swift    # Quota strip under the popover header
│   ├── AgentUsageWindowView.swift   # Quota meters + contribution grids
│   ├── ContributionGridView.swift   # GitHub-style calendar of daily tokens
│   ├── MenuBarStripRenderer.swift   # Menu bar image: mark + system/agent readings
│   └── AgentMarks.swift             # Vector agent logos, template-rendered
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
│   ├── TrackpadWeightService.swift  # MultitouchSupport via dlopen, grams from pressure
│   ├── SystemStatsService.swift      # Live readings + in-memory chart history
│   ├── SystemStats/                  # CPU, GPU, memory and thermal samplers
│   ├── AgentCredentials.swift       # Read-only Claude/Codex credential lookup
│   ├── AgentUsageReaders.swift      # Per-agent usage endpoints & mapping
│   ├── AgentUsageService.swift      # Orchestration, polling, selection
│   ├── AgentLogScanner.swift        # Daily tokens from session logs (cached)
│   ├── GlobalShortcutService.swift  # Carbon hotkey
│   ├── LaunchAtLoginService.swift   # SMAppService
│   ├── ShellRunner.swift            # Shared Process helper
│   └── FluxaError.swift             # Centralized error types
└── Resources/
    ├── fluxa.icns                   # App icon
    ├── menu-icon.pdf                # Menu bar switch mark (from new-icon.svg)
    ├── AgentIcons/                  # Agent marks as vector PDFs + their SVG sources
    └── Info.plist                   # LSUIElement, permissions text, metadata
```

### Design principles

- **MVVM** — views observe one `@Observable` ViewModel; services are implementation details
- **MainActor isolation** — UI state and services run on the main actor; blocking calls (Bluetooth connect) hop off it
- **In-panel navigation** — Customize swaps views inside the `MenuBarExtra`; dedicated tools stay separate and activate in front
- **Adaptive design system** — one semantic palette keeps hierarchy and contrast consistent in Aqua and Dark Aqua
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
| Trackpad Scale | Trackpad reports force only under a capacitive touch | Rest a finger on it, place the object beside it; the strain gauges measure total load |
| Trackpad Scale | `NSEvent.pressure` only fires during a click | Reads `MultitouchSupport` via `dlopen`; layout is validated at runtime, feature hides itself if it changes |
| Agent quotas | Refresh tokens rotate on use | Read-only: an expired token is reported, never renewed behind the agent's back |
| Agent history | No history endpoint exists | Rebuilt from the agents' own session logs |
| Codex history | Child sessions replay a parent's history | Not filtered — measured at 0.08% on one day out of nine |
| Temperatures | Later SoCs do not label die sensors by component | Show one Die Temperature instead of inventing separate CPU/GPU values |
| System history | macOS provides live counters, not an app history log | Keep a rolling 30 minutes in memory; history resets on relaunch |

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

Regenerate the vector marks after editing an SVG (needs `rsvg-convert`, e.g. `brew install librsvg`):

```bash
rsvg-convert -f pdf -o Sources/Fluxa/Resources/menu-icon.pdf new-icon.svg
rsvg-convert -f pdf -o Sources/Fluxa/Resources/AgentIcons/claude.pdf \
  Sources/Fluxa/Resources/AgentIcons/claude.svg
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
