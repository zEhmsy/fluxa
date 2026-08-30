# 01 — Survey vorssaint-utils

Status: ready-for-handoff
Owner: —
Type: research
Spec: —
Blocked by: —
Source: vorssaintapp/vorssaint-utils (whole repo)

## Question

What is in `https://github.com/vorssaintapp/vorssaint-utils`, and which parts are
worth porting into Fluxa?

Produce enough of a survey that the pipeline / telemetry / crypto tickets can be written
against something real rather than against the three words in the effort brief.

Answer at minimum:

- Language, build system, module layout, and licence. **The licence gates everything
  else** — if it does not permit reuse in Fluxa, this effort stops here and becomes a
  clean-room reimplementation with a different shape.
- What the pipeline component actually is: a data pipeline, a build pipeline, a
  processing chain? Its public surface and its concurrency assumptions.
- What telemetry collects, and where it sends it.
- What the crypto component does, which primitives it uses, and whether any of its
  security properties are load-bearing.
- For each: does Fluxa have a place for it, or is this a solution without a problem here?

## Notes

Do not begin any Swift work off the back of this ticket. Its only output is the survey
and a set of follow-up tickets.

## Answer

Surveyed 2026-08-30 via the GitHub API (tree listing and repo metadata only — **no upstream
source file was read**, see "Clean-room hygiene" below).

### 1. Licence — this is a blocker

| | Fluxa | vorssaint-utils |
| --- | --- | --- |
| Licence | **Apache-2.0** | **GPL-3.0** |

Compatibility runs **one way only**: Apache-2.0 code may be absorbed into a GPL-3.0
project, never the reverse. Copying, translating or deriving Swift from this repo into
Fluxa makes the result a GPL-3.0 derivative work. That would require Fluxa to be
relicensed GPL-3.0 *and* to offer complete corresponding source to every recipient of the
DMG — which conflicts with how Fluxa is distributed today (signed binary DMG + Sparkle
feed, per `HANDOFF.md`).

A line-by-line translation from Swift to Swift is not a laundering step. It is a
derivative work in the ordinary sense.

**The effort as briefed — "porting di funzionalità" — cannot proceed under the current
licences.** This ticket stops here pending the owner's decision (see Options).

### 2. What the repo actually is

- **Free and open-source macOS menu bar toolkit**, homepage `vorssaint.com`, 13.6k stars,
  457 forks, 292 open issues. Active (pushed 2026-08-29).
- Swift, SPM, single `Sources/Vorssaint` target plus a `FanControlHelper` helper binary.
- **415 Swift files** across `Services` (232), `UI` (104), `Core` (63), `App` (7).
- Roughly 60 feature services: QuickTools, Recorder, CommandBar, Switcher, Audio,
  Cleaner, Clipboard, Display, Finder, FanControl, Snippets, SuperKey, WindowLayout,
  Uninstall, Homebrew, Shelf, RadialMenu…

**It is the same product category as Fluxa, roughly 6× the size.** Fluxa is 69 Swift
files. This is not a utility library to draw from; it is a competing application.

### 3. The three named components do not exist as named

The brief asks for Pipeline, Telemetry and Crypto. None is a module upstream:

| Brief | Nearest upstream reality |
| --- | --- |
| Pipeline | No such component. Closest is `Services/Metrics/` (16 files): `DiskSampler`, `NetworkSampler`, `PowerSampler`, `PeripheralBatterySampler`, `MonitorSamplingPolicy`, `TemperatureSensorSelector`, `MetricFormat`. A sampling layer, not a pipeline. |
| Telemetry | **Nothing.** No analytics, no telemetry, no network sink anywhere in the tree. The `Services/SystemMonitor/` group (4 files) is local threshold alerting, not telemetry. |
| Crypto | **Nothing.** No crypto module. The only adjacent code is `Services/Update/` (4 files) and `Services/AppUpdates/` (2), i.e. update-signature verification. |

So the premise of tickets 03+ was wrong before they were written. Whatever the source of
those three names, it was not this repository.

### 4. Overlap with Fluxa is already near-total in the relevant area

Fluxa already ships its own equivalents of the only part that overlaps:

| Fluxa (exists today) | Upstream counterpart |
| --- | --- |
| `SystemStats/CPUUsageSampler`, `GPUUsageSampler`, `MemorySampler`, `ThermalSensorReader` | `Services/Metrics/*Sampler`, `TemperatureSensorSelector` |
| `UpdateService` (Sparkle, live since 2.6.1) | `Services/Update/UpdateService` |
| `KeepAwakeService`, `AudioOutputService`, `BluetoothAudioService`, `LaunchAtLoginService` | `KeepAwakeManager`, `Services/Audio/`, `Services/Bluetooth/`, `LaunchAtLogin` |

There is little to gain and a licence liability to acquire. Fluxa's `UpdateService` in
particular is a standing production feature that `HANDOFF.md` forbids disturbing.

### 5. Not a source of testing practice

Upstream has exactly **one** test file (`Tests/MetricsTests.swift`) for 415 sources. Do
not look here for a testing model; ticket `02` stands on its own.

### 6. Clean-room hygiene

This survey deliberately read **only** the file tree and repo metadata — never file
contents. That keeps the clean-room option (below) open. If the owner picks it, whoever
writes the Fluxa specification must not read upstream source either; the specification
must be derived from observable behaviour and public docs only.

## Options for the owner

1. **Abandon the port; keep Fluxa Apache-2.0.** Cheapest and safest. Fluxa already has
   the overlapping capability. Close this effort.
2. **Clean-room reimplementation of specific features.** Legal under any licence, but it
   is ordinary feature development with extra process overhead — the value is in the
   feature idea, not in the upstream code. If chosen, name the concrete features you
   want; "pipeline/telemetry/crypto" does not map onto anything real here.
3. **Relicense Fluxa to GPL-3.0.** Makes literal porting legal, but forces source
   distribution and is irreversible for third-party contributions. A product decision,
   not an engineering one.

Recommendation: **option 1 or 2**. Option 2 only with a named feature list.

## Comments

- 2026-08-30, claude — Survey done. Set to `needs-info`: the licence gate fails, and the
  three components named in the brief do not exist upstream.
- 2026-08-30, giuseppe — **Decision: option 2, clean-room.** Fluxa stays Apache-2.0.
  Nothing is ported. Feature *ideas* are taken (not copyrightable), each one designed and
  implemented from scratch against Fluxa's own architecture. Groups **A** (extend the
  metrics Fluxa already samples) and **B** (small self-contained quick actions) selected;
  group C (clipboard history, snippets, window management, mouse tweaks) deferred as
  each is a mini-project. Fan control, alt-tab switcher, Dock preview and app uninstaller
  rejected outright — privileged root helper, private APIs, and destructive file deletion
  respectively. Tickets `03`–`13` written. Ticket resolved.
