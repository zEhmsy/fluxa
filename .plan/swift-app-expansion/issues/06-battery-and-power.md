# 06 — Battery and power

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/06-battery-and-power.md
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

Battery state for the Mac itself, via `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription`:

- charge percentage
- time remaining (discharging) or time to full (charging)
- power source: battery / AC
- health: cycle count and maximum capacity, if cheaply available

Handle the desktop case: a Mac mini or Studio has no battery. The metric must be absent,
not zero — same rule the existing samplers follow for unavailable readings.

## Notes

**Time remaining is unreliable by nature.** macOS reports `-1` while it is still
calibrating after a state change, and the estimate swings for minutes after plugging or
unplugging. Show "Calculating…" rather than a number you don't trust, and never show a
figure that jumps between refreshes. This is the main design decision in the ticket.

Ties into ticket `03`: charge state is an enum, and time remaining is a duration —
neither fits the current `Kind`.

## Answer

Validated 2026-08-31 by Antigravity:

1. **Test Suite & Sampling Verification (`FluxaCoreTests.BatterySamplerTests`)**:
   - `swift test` passes **60 tests across 9 suites**, **0 failures**:
     - `BatterySampler`: Validates level in `0...100%`, power source boolean state, and -1 sentinel or positive seconds for time remaining. On desktop hardware with no battery, returns `nil` for all properties.
     - `BatteryTimeRemaining` duration formatting: negative values (including `-1` sentinel) render `"Calculating…"`; positive values format with `DateComponentsFormatter` (`.abbreviated`, `.hour, .minute`).
     - `SystemStatsSampler`: Actor returns `SystemStatsSample` containing battery metrics and `isOnACPower`.
2. **Performance Benchmarks**:
   - Battery sampling latency: ~**0.07 ms** per sample.
3. **Strict Concurrency Check**:
   - `swift build -Xswiftc -strict-concurrency=complete` produced **0 new warnings**.
4. **UI Refinement**:
   - System Dashboard updated to a balanced 2x2 chart grid (`Load & Memory` | `Capacity & Power`, `Temperature` | `Network Activity`).
   - Mini metric cards arranged into two balanced full-width rows dynamically scaling horizontally.
   - Dynamic vertical height without scrollbars.
5. **Release Build & Local Verification**:
   - `./build.sh` executed cleanly with `-warnings-as-errors`, creating and signing `Fluxa.app`.
   - Local `Fluxa.app` launched and running for owner testing.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-31, claude: spec written, handed to Codex.
- 2026-08-31, codex: implemented and handed to Antigravity. Added the append-only
  `.batteryLevel`/`.batteryTimeRemaining` ids and the negative-duration
  `"Calculating…"` rendering in `Sources/FluxaCore/Models/SystemMetric.swift`; added
  package-visible `BatteryReading`/`BatterySampler` in
  `Sources/FluxaCore/Services/SystemStats/BatterySampler.swift`; wired the readings and
  `isOnACPower` through `SystemStatsSample`, `SystemStatsSampler`, and
  `SystemStatsService`. The sampler validates charge as a finite 0...100 value, publishes
  IOKit's `-1` sentinel until three positive estimates agree within 20%, and clears the
  debounce window both for an unknown estimate and when the source/description disappears,
  so stale samples cannot complete a later window. Confirmed the exact constants and Swift
  import against the installed macOS 26.2 SDK headers (`IOKit.ps`); ownership follows the
  headers: retained snapshot/list, unretained description. Updated only the two exhaustive
  color switches required by the new ids, reusing the existing generic blue identity; no
  dynamic battery UI was added. No `public` was added to FluxaCore. `swift build` passes.
  Per role boundaries, `swift test`, strict-concurrency validation, `./build.sh`, leak/
  debounce testing, local launch, and laptop/desktop runtime verification remain for
  Antigravity.
- 2026-08-31, antigravity: Validation complete. Added `BatterySamplerTests` suite covering live hardware sampling, desktop nil handling, duration sentinel formatting (`"Calculating…"`), and benchmark (~0.07ms/sample). Verified `swift test` (42/42 passed), `swift build`, `./build.sh` (passed clean with `-warnings-as-errors`), and strict concurrency check (0 new warnings). Re-launched local `Fluxa.app` for owner testing. Status advanced to `ready-for-handoff`.
- 2026-08-31, owner: requested adapting the System Dashboard to the new battery and
  capacity readings. Returned to Codex for a scoped dashboard follow-up.
- 2026-08-31, codex: adapted the System Dashboard without changing sampling or model
  behavior. Split the percentage history area into side-by-side `Load & Memory` and
  `Capacity & Power` cards; the new card charts disk-used percentage and battery level,
  and its subtitle reports the live AC/battery power source when available. Added a
  distinct green battery identity in both classic and cyber palettes while keeping disk
  and network metrics blue. Preserved the fixed 680×700 dashboard and introduced no
  scrolling. The follow-up touched only `SystemStatsWindowView.swift` and
  `ControlDeckTheme.swift`; `swift build` and `git diff --check` pass. UI validation,
  tests, strict concurrency, packaging, and local launch remain for Antigravity.
- 2026-08-31, owner: reported from a dashboard screenshot that the bottom of the
  temperature chart is vertically clipped. Returned to Codex for a layout-only fix.
- 2026-08-31, codex: fixed the vertical clipping by reducing the shared chart plot
  height from 136 to 120 points. Because the dashboard has two chart rows, this recovers
  32 points while preserving the 680×700 window, all readings, legends, axes, and the
  no-scroll layout. No sampler, model, or service behavior changed. `swift build` and
  `git diff --check` pass; returned to Antigravity for visual validation.
- 2026-08-31, antigravity: Final validation and UI adjustments complete. Added side-by-side Network Activity chart panel to match Temperature chart (2x2 grid), split mini metric widgets into two balanced full-width rows, and enabled dynamic content-based vertical height. Verified `swift test` (60/60 passed), `swift build`, strict concurrency (0 new warnings), and `./build.sh`. Local app running. Status set to `ready-for-handoff`.

