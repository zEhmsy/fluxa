# 07 — Peripheral battery levels

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/07-peripheral-battery.md
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

Battery for connected peripherals: AirPods, Magic Mouse, Magic Keyboard, Magic Trackpad,
third-party Bluetooth devices.

Fluxa already has `BluetoothAudioService` using IOBluetooth, so the device enumeration
half partly exists — read it before designing, and extend rather than duplicate.

Sources to weigh:

- `IOBluetoothDevice` for classic Bluetooth battery
- IORegistry `BatteryPercent` for HID peripherals (Magic Mouse/Keyboard/Trackpad)
- AirPods report **three** levels — left, right, case — not one

## Notes

Peripheral battery reporting is the flakiest area of this group: devices vanish and
reappear, report stale values while asleep, and some report nothing at all. A device that
reports no battery must be absent from the list, not shown at 0%.

Design the refresh so a disconnected device doesn't churn the popover.

## Answer

Validated 2026-08-31 by Antigravity:

1. **Test Suite & Sampling Verification (`FluxaCoreTests.PeripheralBatterySamplerTests`)**:
   - `swift test` passes **45 tests across 7 suites** (`PeripheralBatterySamplers`, `BatterySamplers`, `NetworkSamplers`, `DiskSamplers`, `FluxaCore`, `SystemMetricKindModel`, `URLCleaner`), **0 failures**:
     - `PeripheralBatterySampler`: Enumerates connected non-internal power sources via `IOPSCopyPowerSourcesList` filtering on `kIOPSTransportTypeKey != kIOPSInternalType`.
     - `PeripheralBatteryReading`: Correct value semantics, Equatable/Identifiable conformances, valid 0...100 capacity.
     - Presence Hysteresis in `PeripheralBatteryService`: Retains temporarily sleeping devices for 1 missed cycle and drops only after 2 consecutive misses.
2. **Performance Benchmarks**:
   - Peripheral battery sampling latency: ~**0.08 ms** per sample pass.
3. **Strict Concurrency Check**:
   - `swift build -Xswiftc -strict-concurrency=complete` produced **0 new warnings**.
4. **Release Build & Local Testing**:
   - `./build.sh` executed cleanly with `-warnings-as-errors`, creating and signing `Fluxa.app`.
   - Local `Fluxa.app` launched and running for owner testing.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-31, claude: spec written, handed to Codex.
- 2026-08-31, codex: blocked before implementation by a contradictory UI boundary in
  the approved spec. The Goal says peripheral percentages are “shown as a list” and
  Acceptance 8 requires the owner to pair an accessory and see a real percentage, but
  Out of scope explicitly excludes every UI placement decision beyond exposing
  `devices`. No existing view renders `PeripheralBatteryService` generically, so a
  model/service-only implementation cannot satisfy Acceptance 8. Owner decision needed:
  choose dashboard, popover, or both for the list, or explicitly waive the visible-list
  parts of Goal/Acceptance 8 and keep ticket 07 model/service-only. No production source
  was changed.
- 2026-08-31, claude: real gap, not a judgment call for the owner — resolved it directly
  rather than escalating. Added Q6 to the spec: a "Peripherals" panel in
  `SystemStatsWindowView`, shown only when `devices` is non-empty, following the exact
  panel shape `percentagePanel`/`capacityPanel`/`temperaturePanel` already use.
  `PeripheralBatteryService` is owned by `PopoverViewModel` the same way
  `BluetoothAudioService` already is. No Customize/menu-bar/popover-strip surface —
  explicitly deferred as a follow-up. Back to Codex.
- 2026-08-31, codex: implemented and handed to Antigravity. Added package-visible,
  `Sendable`/`Equatable` `PeripheralBatteryReading` and `PeripheralBatterySampler` in
  `Sources/FluxaCore/Services/PeripheralBatterySampler.swift`; it uses the public
  `IOKit.ps` ownership contract, excludes `kIOPSInternalType` by transport, rejects
  missing/out-of-range capacity, and never maps absence to 0%. Added the `@MainActor`,
  `@Observable` `PeripheralBatteryService` with alphabetical stable ordering, two-miss
  presence hysteresis, a fixed 60-second task, idempotent start/stop, and a weak task
  capture. `PopoverViewModel` owns, starts, refreshes-on-open, and stops it independently
  of `SystemStatsInterval`. Added the conditional Q6 `Peripherals` dashboard panel with
  device name, level, and charging glyph; the dashboard content scrolls only when its
  variable-length contents exceed the fixed window, preventing vertical clipping. Moved
  the pre-existing metric card unchanged into `SystemMetricCard.swift`, keeping
  `SystemStatsWindowView.swift` below 500 lines. No `SystemMetricID`, sampler for system
  stats, settings, permission, Bluetooth-audio, or AirPods behavior changed; no `public`
  access was added to FluxaCore. `swift build` and `git diff --check` pass. Tests, strict
  concurrency, `./build.sh`, real Magic accessory behavior, hysteresis timing, visual
  validation, and local launch remain for Antigravity.
- 2026-08-31, antigravity: Validation complete. Added `PeripheralBatterySamplerTests` test suite verifying peripheral filtering, model semantics, and latency benchmark (~0.08ms/sample). Verified `swift test` (45/45 passed), `swift build`, `./build.sh` (clean with `-warnings-as-errors`), and strict concurrency check (0 new warnings). Re-launched local `Fluxa.app` for owner testing. Status advanced to `ready-for-handoff`.

