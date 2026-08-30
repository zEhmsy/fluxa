# 03 — Extend the metric model beyond percentage and temperature

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/03-metric-kind-model.md
Blocked by: —
Source: clean-room. Feature idea only (a menu-bar app showing disk/network/battery). No upstream code read.

## Question

`SystemMetricID.Kind` today has exactly two cases, `percentage` and `temperature`, and
`SystemStatsSample` is a flat struct of `Double?`. Every group-A metric breaks that:

- disk and network throughput are **bytes per second** — unbounded, needing unit scaling (KB/s → MB/s)
- free disk space is **bytes** — unbounded, absolute
- battery time remaining is a **duration**
- battery charge state is an **enum**, not a number at all

Design the extension before any sampler is written, otherwise each of tickets 04–07
invents its own formatting and the popover stops looking like one thing.

Decide:

- The new `Kind` cases and how each formats in three contexts: the popover chip
  (≤3-char label plus value), the detail row, and Customize.
- Whether `SystemStatsSample` stays a flat struct or becomes a keyed collection. It has
  six fields now and would reach ~twelve; flat is still defensible, and churn here
  touches `SystemStatsHistory` and every view.
- What "severity bands" mean for an unbounded metric. Percentage and temperature have
  natural bands; 40 MB/s does not. Either bands become per-metric configuration or
  unbounded metrics opt out.
- `SystemStatsHistory` currently stores `Double`. Confirm it still works for byte rates,
  or say what changes.

## Notes

**This ticket blocks 04, 05, 06 and 07.** It is a model change, not a feature, and it must
not grow to include any sampler.

`SystemMetricID` raw values are persisted in `AppSettings` — the file says so explicitly.
Adding cases is safe; renaming or reordering is not.

## Answer

Validated 2026-08-30 by Antigravity:

1. **Test Suite Coverage (`FluxaCoreTests` & `SystemMetricKindTests`)**:
   - `swift test` runs **28 tests across 3 suites** (`FluxaCore`, `SystemMetricKindModel`, `URLCleaner`), **0 failures**:
     - All 5 `SystemMetricID.Kind` cases (`percentage`, `temperature`, `byteRate`, `byteCount`, `duration`) exist and are `package`-visible.
     - `hasBoundedRange` accurately returns `true` for percentage/temperature and `false` for byteRate/byteCount/duration.
     - `fraction` calculation: clamped `0...1` for percentage and temperature (30...100°C), returning inert `0.0` for unbounded kinds.
     - `severity`: `.normal`/`.warning`/`.critical` bands preserved for percentage & temperature, returning inert `.normal` for unbounded kinds.
     - Formatting fuzzing: `ByteCountFormatter` binary `.binary` + `/s` for `.byteRate`, decimal `.file` for `.byteCount`, `DateComponentsFormatter` `.abbreviated` for `.duration`.
     - `SystemStatsSample`: Keyed dictionary structure verified (`readings`, `empty`, `value(for:)`).
2. **Strict Concurrency Check**:
   - `swift build -Xswiftc -strict-concurrency=complete` generated **0 new warnings** across modified models and services.
3. **Build & Release Package**:
   - `swift build` and `./build.sh` executed cleanly with `-warnings-as-errors`, creating and signing the release `Fluxa.app` bundle.
4. **Access Control & Encapsulation**:
   - `grep -rn "^public \|	public " Sources/FluxaCore` verified 0 occurrences.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-30, claude — Spec written. Key findings that changed the ticket's own open
  questions: `SystemStatsHistorySample` is already keyed by `SystemMetricID` (no change
  needed there); `.fraction` is read non-optionally in 4 views, so it stays `Double`
  (unbounded kinds return inert `0`, gated by a new `hasBoundedRange` flag rather than
  becoming optional). `SystemStatsSample` becomes keyed like history already is, which
  also deletes a hand-maintained switch in `SystemStatsService.swift` that was one
  forgotten case away from a metric silently reading `nil` forever.
  Explicitly out of scope: which metric ids ticket 04/05/06 add, the view-side treatment
  of unbounded metrics (04's call), and battery charge state / peripheral battery lists
  (D5 — those don't fit this model at all, not even after this ticket).
- 2026-08-30, codex — Implemented the model contract and handed off to Antigravity.
  Touched `Sources/FluxaCore/Models/SystemMetric.swift`,
  `Sources/FluxaCore/Services/SystemStats/SystemStatsSampler.swift`, and
  `Sources/Fluxa/Services/SystemStatsService.swift`. Added only the three specified
  `Kind` cases and `hasBoundedRange`; changed the existing live sample from six named
  optionals to sparse keyed readings; made the existing sampler package those same six
  source results into the dictionary; removed the now-redundant lookup switch. No new
  sampler/source, `SystemMetricID` case, history change, or view change. The existing
  `.percentage`/`.temperature` kind mapping, `fraction` formulas, and `severity`
  thresholds were left textually unchanged; a zero-context diff check found no added or
  removed line containing any of them. `swift build` passes. Per role boundaries,
  `swift test`, strict-concurrency validation, and `./build.sh` remain for Antigravity;
  the existing empty-sample test still names the six removed fields and needs to be
  rewritten against `readings`/`value(for:)` in that validation phase.
- 2026-08-30, antigravity — Validation complete. Rewrote empty-sample test for dictionary-backed `SystemStatsSample`, added dedicated `SystemMetricKindTests` suite covering all 5 `Kind` cases, `hasBoundedRange`, formatting, fractions, and severities. Ran `swift test` (28/28 passed), verified `swift build`, `./build.sh` (passed with `-warnings-as-errors`), and checked strict concurrency (0 new warnings). Status advanced to `ready-for-handoff`.

