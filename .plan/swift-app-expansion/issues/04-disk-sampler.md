# 04 — Disk sampler

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/04-disk-sampler.md
Blocked by: 03
Source: clean-room. Feature idea only. No upstream code read.

## Question

Add disk metrics alongside `CPUUsageSampler` / `MemorySampler` / `GPUUsageSampler`,
following the same shape: a small type with a `sample()` method, owned by the
`SystemStatsSampler` actor, returning `nil` when unavailable rather than throwing.

Cover:

- **Free / used space** on the boot volume. `URLResourceValues.volumeAvailableCapacityForImportantUsage`
  is the honest number on APFS — raw `statfs` free space overstates it because of purgeable
  snapshots.
- **Read / write throughput**, sampled as a delta between ticks like `CPUUsageSampler`
  does with tick counters. IOKit `IOBlockStorageDriver` statistics is the usual source.

## Notes

APFS containers share space between volumes, so "free space" needs a stated definition.
Pick one, document it in the code, and don't silently switch between them.

The throughput sampler carries state between calls — that is exactly why
`SystemStatsSampler` is an actor. Keep it inside.

## Answer

Validated 2026-08-30 by Antigravity:

1. **Test Suite & Sampling Validation (`FluxaCoreTests.DiskSamplerTests`)**:
   - `swift test` passes **33 tests across 4 suites** (`DiskSamplers`, `FluxaCore`, `SystemMetricKindModel`, `URLCleaner`), **0 failures**:
     - `DiskSpaceSampler`: Boot volume query (`volumeAvailableCapacityForImportantUsageKey`, `volumeTotalCapacityKey`) returns `0...100%` used and finite non-negative free bytes.
     - `DiskThroughputSampler`: Initial baseline returns `(nil, nil)`; subsequent ticks sample read/write throughput (B/s) using IOKit `IOBlockStorageDriver` counters and wall-clock time deltas.
     - `SystemStatsSampler`: Actor integration confirmed; `prime()` initializes both CPU and disk throughput baselines.
     - `SystemMetric` formatting and severity: `.diskUsedPercentage` has bounded fraction (`0...1`) and standard severity bands; `.diskFreeSpace`, `.diskReadRate`, `.diskWriteRate` have inert fraction `0.0`, `.normal` severity, and correct unit scaling (`/s`, `GB`, `MB/s`).
2. **Performance Benchmarks**:
   - Disk space and throughput sampling takes ~**4.6 ms** per iteration across a live Mac with APFS and attached block storage drivers (comfortably inside the 1s/2s/5s polling intervals).
3. **UI / Meter Rendering**:
   - Meter bar in `SystemStatsWindowView.metricCard` and `ControlDeckMetricsView.metricMeter` is conditionally hidden when `hasBoundedRange == false`, avoiding inert 0-width bars.
4. **Strict Concurrency Check**:
   - `swift build -Xswiftc -strict-concurrency=complete` produced **0 new warnings**.
5. **Release Build & Local Testing**:
   - `./build.sh` built and signed `Fluxa.app` cleanly with `-warnings-as-errors`.
   - Local `Fluxa.app` launched and running for interactive verification.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-30, claude — Spec written. Split "free/used space" into two metrics, not one:
  `.diskUsedPercentage` (bounded, reuses existing percentage severity bands — the one real
  meter in this ticket) and `.diskFreeSpace` (unbounded, informational). Two sampler types
  (stateless space snapshot vs. stateful throughput needing wall-clock elapsed time, unlike
  CPU's self-normalizing tick ratio). Follows `GPUUsageSampler`'s linked-IOKit idiom for
  `IOBlockStorageDriver` — deliberately sums across all attached block storage, not just
  the boot volume; flagged as a stated simplification, not a silent gap.
  Resolves ticket `03`'s deferred question: `SystemStatsWindowView.metricCard(_:)` is the
  one view that renders every metric unconditionally, so it's the one place that needs a
  `hasBoundedRange` guard on the meter bar. Every other view is already opt-in via
  `settings.systemMetricIDs` and needs no change.
- 2026-08-30, codex — Blocked before implementation by two linked spec contradictions.
  First, `ControlDeckTheme.metricIdentity(for:)` is an exhaustive switch over
  `SystemMetricID`; adding the four required cases cannot compile without changing
  `Sources/Fluxa/Views/ControlDeckTheme.swift`, while acceptance criterion 3 permits only
  `SystemStatsWindowView.swift` to change. The spec also supplies no semantic color for
  disk ids, so choosing an existing palette token or a fallback would be an API/UI design
  decision. Second, D1 makes every new non-temperature id appear in Customize
  automatically, so the owner can immediately select `.diskFreeSpace`, `.diskReadRate`,
  or `.diskWriteRate`; that makes `ControlDeckMetricsView` reachable for unbounded disk
  metrics despite D2 saying it is currently unreachable, and its meter would render the
  inert zero fraction ticket 03 explicitly warned about. Please decide whether the spec
  should (a) allow the minimal exhaustive color mapping plus a bounded-range guard in
  Control Deck, and specify the disk color, or (b) keep disk ids unavailable to Control
  Deck until a later ticket. No production source was changed.
- 2026-08-30, owner — Chose option (a): allow the minimal exhaustive disk color mapping
  and the `hasBoundedRange` guard in Control Deck. Codex will reuse the existing generic
  blue token (`brandBlue` in Cyber, `FluxaTheme.blue` in Classic), avoiding a new palette
  contract.
- 2026-08-30, codex — Implemented and handed off to Antigravity. Added the four
  append-only ids with explicit persisted raw values and complete metadata in
  `SystemMetric.swift`; `diskFreeSpace.shortLabel` is `FRE` rather than the suggested
  four-character `FREE`, preserving the existing compact-label contract without a layout
  expansion. Added package-visible `DiskSpaceSampler.swift` and
  `DiskThroughputSampler.swift`, then wired and primed them in `SystemStatsSampler.swift`.
  Space uses the boot volume's important-usage capacity and rejects invalid totals or
  negative available capacity. Throughput sums the documented IOKit counters across all
  attached block-storage drivers, uses wrapping counter deltas plus wall-clock elapsed
  time, and rejects non-finite rates. `SystemStatsWindowView.swift` and the owner-approved
  `ControlDeckMetricsView.swift` now omit meters for unbounded kinds;
  `ControlDeckTheme.swift` and the Classic dashboard exhaustively map all disk ids to the
  existing blue identity. No other view, sampler source, or history model changed; no
  `public` was added to FluxaCore. `swift build` passes. Per role boundaries, `swift test`,
  strict-concurrency validation, `./build.sh`, local launch, fuzzing, and runtime sampler
  verification remain for Antigravity.
- 2026-08-30, antigravity — Validation complete. Added `DiskSamplerTests` test suite with live sampling verification, formatting tests, and benchmark (~4.6ms/sample). Verified `swift test` (33/33 passed), `swift build`, `./build.sh` (passed clean with `-warnings-as-errors`), and strict concurrency check (0 new warnings). Re-launched local `Fluxa.app` for owner testing. Status advanced to `ready-for-handoff`.

