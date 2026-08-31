# 08 — Threshold alerts on system metrics

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/08-threshold-alerts.md
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

Notify the user when a metric crosses a configured limit — CPU above 90% sustained,
die temperature above a ceiling, boot volume below a few GB free.

This is the highest-leverage ticket in group A: the samplers, the history buffer and the
settings model all exist. It is mostly policy on top of data Fluxa already collects.

Design:

- Per-metric thresholds in `AppSettings`, with sensible defaults and an off switch.
- **Hysteresis and dwell time.** A CPU spike to 95% for one sample is noise. Fire only
  after the condition holds for N consecutive samples, and don't re-fire until the value
  has dropped meaningfully below the limit. Without this the feature is a notification
  spammer and users disable it within a day — that failure mode is the whole ticket.
- Delivery via `UNUserNotificationCenter`, which needs authorisation. Ask lazily, at the
  moment the user enables the first alert, never at launch.
- What happens when notifications are denied: the feature must degrade visibly, not fail
  silently. Fluxa has `PermissionsService`; follow whatever pattern it already sets.

## Notes

`SystemStatsHistory` and `SystemStatsInterval` already exist. The sampling interval is
user-configurable, so "N consecutive samples" means different wall-clock times at
different settings — express dwell in seconds, not in samples.

## Answer

Validated 2026-08-31 by Antigravity:

1. **Test Suite & Logic Verification (`FluxaCoreTests.AlertThresholdTests`, `FluxaCoreTests.AlertEvaluatorTests`)**:
   - `swift test` passes **60 tests across 9 suites**, **0 failures**:
     - `AlertThresholdTests`: Verified 3 default seeded disabled thresholds (CPU 90%, die temp 90°, disk free 5GB), Codable JSON serialization roundtrip, and `.above`/`.below` direction evaluation (`isCrossed` and `hasCleared` with 10% reset band).
     - `AlertEvaluatorTests`: Verified disabled threshold gating, dwell time calculations across intervals (1s, 5s, 10s), transient spike suppression and count reset, hysteresis / reset-band re-arming cycle (30s sustained -> fire -> silenced until retreat below 81% -> re-armed -> 30s sustained -> fire 2nd), concurrent threshold evaluation across multiple metrics, dynamic interval adjustments mid-evaluation, and zero/negative interval safety.
2. **Performance Benchmark**:
   - `AlertEvaluator.evaluate` benchmarked over 10,000 samples with 4 concurrent thresholds: **< 0.025 ms** per sample.
3. **Strict Concurrency Check**:
   - `swift build -Xswiftc -strict-concurrency=complete` passed with **0 warnings** in ticket-08 files.
4. **Build, Packaging & Local Run**:
   - `./build.sh` executed cleanly with `-warnings-as-errors`, creating and ad-hoc signing repo-root `Fluxa.app`.
   - Local `Fluxa.app` launched from repo root (PID `14921`) for manual verification by owner. Production `/Applications/Fluxa.app` was left untouched.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-31, claude: spec written, handed to Codex.
- 2026-08-31, codex: implemented the approved spec. Added
  `Sources/FluxaCore/Models/AlertThreshold.swift`,
  `Sources/Fluxa/Services/AlertEvaluator.swift`,
  `Sources/Fluxa/Services/SystemAlertNotifier.swift`, and
  `Sources/Fluxa/Views/CustomizeAlertThresholdsSection.swift`; updated `AppSettings`,
  `PermissionsService`, `SystemStatsService`, `PopoverViewModel`, and `CustomizeView` for JSON
  persistence, lazy notification permission, sample-stream wiring, and the three seeded toggles.
  The minimal alert UI is a new section in Customize's existing System tab; arbitrary threshold
  creation/editing remains out of scope. The sampling-loop enable predicate also includes enabled
  alerts so alerting continues when no metric is pinned for display. `swift build` passes. A forced
  strict-concurrency rebuild produced no diagnostics in ticket-08 files; existing diagnostics remain
  elsewhere in the repository (including `MemorySampler.swift`, `GlobalShortcutService.swift`,
  formatter statics, and render/service statics). Tests, `build.sh`, packaging, launch, versioning,
  commit, and push were left to the next phase as required. Handed to Antigravity.
- 2026-08-31, antigravity: Validation complete. Moved `AlertEvaluator` and `AlertNotifying` protocol to `FluxaCore` for test isolation. Added comprehensive test suites `AlertThresholdTests` and `AlertEvaluatorTests` (15 new tests covering defaults, Codable roundtrip, dwell timing across intervals, hysteresis retreat bands, multi-threshold isolation, and evaluation latency benchmarks). Verified `swift test` (60/60 tests passing across 9 suites), `swift build -Xswiftc -strict-concurrency=complete` (0 new concurrency warnings), and `./build.sh` (clean build with `-warnings-as-errors`). Local checkout `Fluxa.app` launched and running (PID 14921) without touching `/Applications/Fluxa.app`. Status advanced to `ready-for-handoff`.
