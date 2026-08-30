# Spec 03 — Extend the metric model beyond percentage and temperature

Ticket: `issues/03-metric-kind-model.md`
Author: claude
Date: 2026-08-30

## Goal

Give `SystemMetricID`/`SystemMetric`/`SystemStatsSample` enough shape to carry disk,
network, and battery-time readings (tickets `04`–`06`), without 04–06 each inventing
their own formatting or fighting the same design fight independently.

**Model only.** No sampler, no new `SystemMetricID` case, no view change beyond what
D4 forces. Tickets `04`–`06` add the actual metric ids and samplers on top of this.

## Grounding — what's already there

Read before implementing, because it changes two of the ticket's open questions:

- `SystemStatsHistorySample` (`Sources/FluxaCore/Models/SystemStatsHistory.swift`)
  **already** stores `[SystemMetricID: Double]`, not a flat struct. Only the live-sample
  type (`SystemStatsSample`) and the display type (`SystemMetric`) are still shaped
  around named fields / a single `Double`.
- `.fraction` is read **non-optionally** to size a bar's width in four views:
  `ControlDeckMetricsView.swift:120,213`, `ControlDeckTheme.swift`, `SystemStatsStripView.swift:105`,
  `SystemStatsWindowView.swift:135`. Making it `Double?` ripples into all four. Don't.
- `SystemStatsSample.value(for:)` in `Sources/Fluxa/Services/SystemStatsService.swift:166-176`
  is a hand-maintained switch mapping each `SystemMetricID` to one of six named optional
  fields. Every new metric id means one more named field **and** one more switch case —
  two places to forget one, which is exactly the kind of drift ticket `02`'s access-level
  discipline was trying to avoid elsewhere.

## D1 — Three new `Kind` cases, nothing more

```swift
package enum Kind {
    case percentage
    case temperature
    /// Bytes per second, e.g. disk or network throughput. Unbounded.
    case byteRate
    /// Bytes, absolute, e.g. free disk space. Unbounded.
    case byteCount
    /// Seconds, e.g. battery time remaining. Unbounded. A metric of this kind may also
    /// be legitimately *unknown* (see the note below) — that is a property of the
    /// reading, not of the kind, and stays outside this enum.
    case duration
}
```

No case for battery charge percentage — reuse `.percentage`, it already means "0...100,
shown as N%." No case for battery charge *state* (AC/battery) or peripheral battery
*lists* — see D5, they don't belong in `SystemMetricID` at all.

### Formatting (`SystemMetric.displayText`)

```swift
case .byteRate:
    return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) + "/s"
case .byteCount:
    return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
case .duration:
    // DateComponentsFormatter, .abbreviated, allowedUnits [.hour, .minute].
    // A value that doesn't fit "Nh Nm" (e.g. still calibrating) is not this type's
    // problem — see the "unknown duration" note below.
```

Use `.binary` (1024-based, "MiB/s"-shaped but Apple's formatter prints "MB/s") for
throughput and `.file` (1000-based, matches Finder's "on-disk size") for absolute free
space — that's the same convention macOS itself uses between Activity Monitor's network
graph and Finder's "Available" figure, so Fluxa's numbers won't look wrong next to them.

**A `duration` value that isn't known yet is not representable as a `Double` you'd want
formatted.** Ticket `06` already flagged that macOS reports `-1` while calibrating and
that this must show "Calculating…", not a number. That means ticket `06`'s battery
sampler does **not** feed an unresolved reading through `SystemMetric` at all — it either
omits the value that pass (same as any other unavailable metric, per `SystemStatsSample`'s
existing "nil = not this pass" convention) or the consuming view checks for the sentinel
before formatting. Pick one when `06` is written; this spec doesn't resolve it, only flags
that `displayText` for `.duration` must never be asked to format a negative number.

### `fraction` and `severity` for unbounded kinds

`percentage` and `temperature` have a natural 0...1 range and universal severity bands.
Byte rates, byte counts, and durations don't — "42 MB/s" isn't critical or normal in the
abstract, and a fixed byte-count ceiling would be a made-up number. Given `.fraction` is
read non-optionally by four views (see Grounding), the contract that avoids touching all
four right now:

```swift
package var fraction: Double {
    switch id.kind {
    case .percentage:   /* unchanged */
    case .temperature:  /* unchanged */
    case .byteRate, .byteCount, .duration:
        return 0   // inert, not "empty" or "critical" — see hasBoundedRange below
    }
}

package var severity: Severity {
    switch id.kind {
    case .percentage:   /* unchanged */
    case .temperature:  /* unchanged */
    case .byteRate, .byteCount, .duration:
        return .normal
    }
}
```

Add one new flag so a view can tell *why* fraction is 0, instead of rendering a
permanently-empty bar next to a real number:

```swift
package extension SystemMetricID.Kind {
    /// Whether `fraction`/`severity` carry real meaning for this kind, or are inert
    /// placeholders. A view showing a meter bar should check this before trusting
    /// `fraction` — an unbounded metric should render as a plain numeric row instead.
    var hasBoundedRange: Bool {
        switch self {
        case .percentage, .temperature: return true
        case .byteRate, .byteCount, .duration: return false
        }
    }
}
```

**Whoever writes ticket `04` (first unbounded metric to actually ship) makes the view-side
call** — plain row vs. some other treatment — and that becomes the pattern `05`/`06`
follow. This ticket only guarantees the flag exists so that decision has something to key
off; it does not touch `ControlDeckMetricsView`, `SystemStatsStripView`, or
`SystemStatsWindowView` itself.

## D2 — `SystemStatsSample` becomes keyed, matching `SystemStatsHistorySample`

Replace the six named fields with the same shape history already uses:

```swift
package struct SystemStatsSample: Sendable {
    package var readings: [SystemMetricID: Double]
    package static let empty = SystemStatsSample(readings: [:])
    package func value(for id: SystemMetricID) -> Double? { readings[id] }
}
```

`SystemStatsSampler.sample()` (`Sources/FluxaCore/Services/SystemStats/SystemStatsSampler.swift`)
builds the dictionary directly instead of positional fields:

```swift
package func sample() -> SystemStatsSample {
    let temperatures = thermal.read()
    var readings: [SystemMetricID: Double] = [:]
    readings[.cpuUsage] = cpu.sample()
    readings[.gpuUsage] = gpu.sample()
    readings[.memoryUsage] = memory.sample()
    readings[.cpuTemperature] = temperatures.cpu
    readings[.gpuTemperature] = temperatures.gpu
    readings[.dieTemperature] = temperatures.die
    return SystemStatsSample(readings: readings)
}
```

Delete the `private extension SystemStatsSample { func value(for:) }` switch in
`SystemStatsService.swift:166-176` entirely — it's now redundant with the struct's own
`value(for:)`. **This is the actual payoff of this change**: today, adding a
`SystemMetricID` case means remembering to update three places (the enum, the sample
struct's fields, and this switch) or the new metric silently reads as `nil` forever with
no compiler error. The keyed dictionary collapses that to one place. Tickets `04`–`06`
each just add `readings[.newID] = ...` in their sampler; nothing else in
`SystemStatsService` changes.

`SystemStatsService.apply(_:)` (line 134) is unaffected beyond this — it already iterates
`SystemMetricID.allCases` and calls `sample.value(for: id)`, which keeps working verbatim
against the new struct.

## D3 — Nothing else moves

`SystemMetric` stays a `struct` with a single `let value: Double`. It does not need to
become a dictionary or a keyed collection — one `SystemMetric` already represents one
resolved reading for one id; that shape doesn't change just because more ids exist.

`SystemStatsHistorySample` needs no change — it was already correctly shaped for this.

## Out of scope (explicitly deferred to 04/05/06)

- Which new `SystemMetricID` cases exist (`.diskFree`, `.diskReadRate`, whatever `04`
  decides to call them) — not this ticket.
- The view-side treatment for `hasBoundedRange == false` metrics — first unbounded
  ticket's call, see D1.
- Battery charge state (AC/battery) and peripheral battery lists — see D5, out of the
  `SystemMetricID` model entirely, not just out of this ticket.
- The "duration not yet known" sentinel/representation — flagged for `06` to resolve,
  not resolved here.

## D5 — What does *not* fit this model, so 06/07 don't try to force it

- **Battery charge state** (AC vs. battery, cycle count, health) is discrete/structural,
  not a meter reading. It does not become a `SystemMetricID` case. It belongs on a small
  dedicated type ticket `06` introduces alongside `.batteryLevel` (which *does* fit —
  it's `.percentage`).
- **Peripheral battery levels** (ticket `07`) are a *list* of devices, each with its own
  level — not a single scalar at all. Forcing "AirPods left/right/case" into three more
  `SystemMetricID` cases would be wrong twice over: the set of connected peripherals is
  dynamic, and `SystemMetricID` today assumes a fixed, enumerable set persisted in
  `AppSettings.actionOrder`-style storage. Ticket `07` needs its own model type; it is
  not an extension of this one.

## Acceptance

1. `SystemMetricID.Kind` has 5 cases: `percentage`, `temperature`, `byteRate`,
   `byteCount`, `duration`. All `package`, matching ticket `02`'s access convention.
2. `hasBoundedRange` exists and is correct for all 5 cases.
3. `SystemMetric.displayText` formats all 5 kinds without crashing on `0`, negative, or
   very large values (fuzz these — Antigravity's job, not this ticket's, but don't hand
   off code that traps on them).
4. `SystemStatsSample` is keyed by `SystemMetricID`; the duplicate `value(for:)` switch in
   `SystemStatsService.swift` is deleted.
5. `swift test`, `swift build`, `./build.sh` all pass. No new strict-concurrency warnings.
6. No existing view file changes. `fraction`/`severity` for `.percentage`/`.temperature`
   are byte-for-byte the same behavior as before this ticket.
7. No `SystemMetricID` case added, renamed, or reordered — only `Kind` grows.

## Risks

- **Silently wrong severity.** If a future ticket adds a `byteRate` metric and some view
  code path checks `severity` without checking `hasBoundedRange` first, it'll render as
  permanently `.normal` (never alerts, never colors) rather than failing loudly. Point
  ticket `08` (threshold alerts) at this explicitly when it's written — thresholds for
  unbounded metrics must be a separate mechanism, not a reuse of `severity`.
- **`Int64(value)` in the byte formatters** traps on `NaN`/`infinity`/out-of-range
  `Double`. Samplers feeding `.byteRate`/`.byteCount` must guarantee finite, non-negative
  values before they reach `SystemMetric` — state this as a precondition in `04`/`05`'s
  sampler code, don't guard defensively here and hide a sampler bug.
