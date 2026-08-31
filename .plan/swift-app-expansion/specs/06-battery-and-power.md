# Spec 06 — Battery and power

Ticket: `issues/06-battery-and-power.md`
Author: claude
Date: 2026-08-31

## Goal

Battery charge, power source, and a trustworthy time estimate, read via
`IOPSCopyPowerSourcesInfo`/`IOPSGetPowerSourceDescription`. Absent, not zero, on a
Mac with no battery — same rule every existing sampler follows.

## P1 — This does not fit `SystemMetricID`/`Kind` as designed, and that's fine

Every existing metric is one `Double` per id. Battery is three different shapes at once:

- charge — a real 0…100 percentage, `.percentage` fits exactly
- power source — `AC` / `Battery`, a two-state enum, not a number at all
- time remaining — a duration, but one that is frequently *unknown* even when the battery
  itself is present and readable (see P3)

Splitting these into separate `SystemMetricID` cases the way ticket `04` split disk into
four cases works for charge and time remaining, but power source doesn't reduce to a
`Double` without a lossy encoding (`0.0`/`1.0` as a fake percentage would trip
`.percentage`'s severity bands and display as "0%"/"100%" in every view that doesn't know
better). Encoding source as a third `Kind` case that ignores its `Double` payload works,
but every one of `displayText`/`fraction`/`severity` in `SystemMetric` would need a special
case that reads a sentinel back into an enum — indirection for its own sake.

**Decision: power source is not a `SystemMetricID`.** It's exposed as a separate,
smaller-scoped read alongside the sampler, described in P4. The two numeric readings —
charge and time remaining — do become `SystemMetricID` cases, because they're genuinely
`Double`s that the existing meter/chip/menu-bar machinery already knows how to render.

```swift
case batteryLevel = "system.batteryLevel"      // .percentage
case batteryTimeRemaining = "system.batteryTime" // .duration
```

Metadata:

```swift
case .batteryLevel:         return "Battery"              // title
case .batteryTimeRemaining: return "Battery Time Remaining"

case .batteryLevel:         return "BAT"                  // shortLabel
case .batteryTimeRemaining: return "TIME"

case .batteryLevel, .batteryTimeRemaining: return "battery.100"  // symbolName —
    // static glyph, not the animated/charging variants; see P5 for why the live icon
    // is a view-layer decision, not something `symbolName` encodes.

case .batteryLevel, .batteryTimeRemaining:
    return "No battery on this Mac."                       // unavailableNote
```

`.batteryLevel` reuses `.percentage`'s existing severity bands *for display purposes only*
— it gets the same meter-and-color treatment CPU/memory/disk-used get. Whether "battery
low" should trigger a proactive notification is threshold-alert territory (ticket `08`),
not this one; this ticket only makes the reading exist and render correctly.

## P2 — `.duration`'s existing formatter already does the right thing for a battery

Ticket `03` added `.duration` for exactly this case and `SystemMetric.displayText` already
formats it as `DateComponentsFormatter` with `.hour, .minute` — "2h 14m" is the right shape
for "time remaining." No change needed there. What P3 changes is what value gets fed into
it.

## P3 — The real design problem: what to publish when IOKit says "unknown"

`IOPSGetTimeRemainingEstimate` (or reading `"Time to Empty"`/`"Time to Full Charge"` from
the power source description dict) returns a sentinel — `-1` (`kIOPSTimeRemainingUnknown`)
— while macOS is still calibrating after a state change: plugging in, unplugging, or a
charge-rate change from thermal throttling. This is not a rare edge case; it is the normal
state for the first minute or two after anything changes, and it can persist longer under
load.

The ticket is explicit that showing a number here is worse than showing nothing: a value
that jumps from "3h 12m" to "0h 4m" to "1h 47m" across three consecutive samples erodes
trust in every other reading Fluxa shows, not just this one.

**This must not be modeled as `nil` the way an unavailable metric is.** `nil` from
`SystemStatsSample.value(for:)` means "this Mac can't read this at all" — Customize shows
`unavailableNote`, and the row shouldn't appear if the user never enabled it. "Calculating"
is a different, *temporary* state on a Mac that absolutely has a battery and absolutely
will have a real number again in a minute — collapsing it into the same `nil` would make
the row flicker in and out of Customize's available-metrics list as the estimate blips,
which is its own trust problem.

**Decision: `.batteryTimeRemaining` stays `nil` from the sampler only when there is no
battery at all (desktop Mac). While calibrating, the sampler reports a sentinel `Double`
that the view layer recognizes and renders as "Calculating…" instead of running it through
`DateComponentsFormatter`.**

Concretely, `SystemMetric.displayText` needs one more branch for `.duration`:

```swift
case .duration:
    guard value >= 0 else { return "Calculating…" }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = [.hour, .minute]
    return formatter.string(from: value) ?? ""
```

`value < 0` as the sentinel (mirroring IOKit's own `-1`) rather than a new `Kind` case or
an `Optional<Double>` payload on `SystemMetric` — it keeps `SystemMetric.value` a plain
`Double` (no ripple into `fraction`/`severity`, which already return inert values for
`.duration` regardless of what the number is) and keeps the sentinel check local to the one
formatter branch that needs to know about it. `BatterySampler.sample()` maps IOKit's `-1`
straight through unchanged — no renaming to some other negative constant, so the two are
never out of sync by construction.

**Debounce the raw estimate before it becomes a sample, not after.** Passing IOKit's
value straight through unfiltered would still let a *late* transition from calculating to
a first real number look like a jump (e.g. from "Calculating…" to "4h 02m" is fine and
expected, but two real numbers 40 minutes apart between consecutive samples is the actual
failure mode described in the ticket, e.g. estimate swinging during the first couple
minutes post-plug). `BatterySampler` keeps a small rolling window (last 3 non-sentinel
estimates) and only publishes a real number once the window's readings agree within a 20%
band of each other; outside that band it keeps reporting the sentinel. This is `08`'s
hysteresis idea applied one ticket early, to the estimate itself rather than to an alert —
scoped narrowly here (fixed 20%/3-sample constants, not user-configurable) since making it
tunable is a bigger feature than "don't show a number I don't trust yet."

## P4 — `BatterySampler`: three reads, one type, `AC`/`Battery` exposed separately

```swift
package struct BatteryReading: Sendable {
    package let level: Double?           // 0...100, nil if no battery
    package let timeRemaining: Double?   // seconds, or IOKit's -1 sentinel while calibrating,
                                          // nil if no battery
    package let isOnACPower: Bool?       // nil if the power source itself can't be read —
                                          // distinct from "on battery", never conflated with it
}

struct BatterySampler {
    private var recentEstimates: [Double] = []   // last 3 non-sentinel readings, for P3's debounce

    mutating func sample() -> BatteryReading {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?
                  .takeUnretainedValue() as? [String: Any]
        else {
            return BatteryReading(level: nil, timeRemaining: nil, isOnACPower: nil)
        }

        let level = (description[kIOPSCurrentCapacityKey] as? Int).map(Double.init)
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let powerSourceState = description[kIOPSPowerSourceStateKey] as? String
        let isOnACPower = powerSourceState.map { $0 == kIOPSACPowerValue }

        let key = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        let rawMinutes = (description[key] as? Int) ?? -1
        let timeRemaining = debouncedSeconds(fromRawMinutes: rawMinutes)

        return BatteryReading(level: level, timeRemaining: timeRemaining, isOnACPower: isOnACPower)
    }

    /// Applies P3's 3-sample/20% agreement window. Returns the -1 sentinel, unchanged, while
    /// unresolved.
    private mutating func debouncedSeconds(fromRawMinutes rawMinutes: Int) -> Double? {
        guard rawMinutes >= 0 else {
            recentEstimates.removeAll()
            return -1
        }
        let seconds = Double(rawMinutes) * 60
        recentEstimates.append(seconds)
        if recentEstimates.count > 3 { recentEstimates.removeFirst() }
        guard recentEstimates.count == 3,
              let low = recentEstimates.min(), let high = recentEstimates.max(),
              low > 0, (high - low) / low <= 0.2
        else { return -1 }
        return seconds
    }
}
```

Only one power source is read (`sources.first`) — a Mac has at most one internal battery;
multiple entries in the list only happen with external UPS devices or Bluetooth
accessories, which is exactly ticket `07`'s scope, not this one. Deliberately not
generalized here.

## P5 — Charging/AC state surfaces through `SystemStatsSample`, not `SystemMetricID`

`isOnACPower` (and, folded into it, "is charging" — derivable as `isOnACPower == true &&
level < 100`, no separate field needed since nothing in this ticket needs to distinguish
"on AC, battery full" from "on AC, topping up") doesn't have a `Double` value to publish
through the `readings` dictionary. `SystemStatsSample` grows one more field alongside it,
following the same sparse-optional shape as `readings`:

```swift
package struct SystemStatsSample: Sendable {
    package var readings: [SystemMetricID: Double]
    package var isOnACPower: Bool?     // nil: no battery, or unreadable
    ...
}
```

`SystemStatsSampler.sample()` calls `battery.sample()` once, writes `.batteryLevel` and
`.batteryTimeRemaining` into `readings` from it (skipping the key entirely when the
corresponding reading is `nil`, matching every other sampler's convention), and sets
`isOnACPower` from the same call.

`SystemStatsService` (the `@MainActor` consumer) gains a mirrored
`private(set) var isOnACPower: Bool?`, updated in `apply(_:)` from the sample the same tick
the metrics array updates. This is additive to `SystemStatsService`'s public surface, not a
change to any existing property.

**View-layer consequence, out of scope for implementation here but flagged for whoever
picks it up (likely alongside `07`, when there's an actual charging-state icon set to
design):** `symbolName` for `.batteryLevel` is a fixed `"battery.100"` per P1 — a real
battery UI eventually wants `battery.75`/`battery.25`/`battery.100.bolt` reflecting live
level and charging state, which needs a view that reads both `SystemMetric.value` and
`SystemStatsService.isOnACPower` together. Building that dynamic-icon view is not required
for this ticket to be complete: a static glyph next to a correct percentage and a correct
"Calculating…"/time string is a fully functional, honest reading. Don't gold-plate it here.

## Acceptance

1. `BatteryReading` and `BatterySampler` exist in `Sources/FluxaCore/Services/SystemStats/`,
   `package`-visible.
2. `.batteryLevel` and `.batteryTimeRemaining` exist as `SystemMetricID` cases with full
   metadata.
3. `SystemStatsSample` carries `isOnACPower: Bool?` alongside `readings`.
4. `SystemMetric.displayText`'s `.duration` branch renders "Calculating…" for a negative
   value instead of feeding it to `DateComponentsFormatter`.
5. `BatterySampler` never publishes a `timeRemaining` swing without three consecutive
   readings agreeing within 20% first; a Mac transitioning from empty-known to
   `nil` recent history restarts the window rather than reusing stale samples.
6. A Mac with no battery: `.batteryLevel`, `.batteryTimeRemaining`, and `isOnACPower` are
   all `nil` from every sample — never `0`, never `false` standing in for "no battery."
7. `swift test`, `swift build`, `./build.sh` pass; no new strict-concurrency warnings; no
   `public` in `FluxaCore`.
8. Local build launched per `docs/agents/roles.md` for the owner to try — Battery
   selectable in Customize → System on a laptop.

## Out of scope

Peripheral battery levels — AirPods, Magic Mouse/Trackpad/Keyboard, other Bluetooth
accessories (`07`, and depends on this ticket's `BatterySampler` shape existing first).
Cycle count and maximum-capacity health readings — the ticket calls these out as "if
cheaply available"; `IOPSGetPowerSourceDescription`'s public dictionary doesn't carry
either, and reading them needs `IOKit`'s `AppleSmartBattery` service directly, a
meaningfully different and less-documented API surface. Flagging as a follow-up, not
solving here. Charging-state-aware battery icon (P5). Low-battery notifications (`08`).

## Risks

- **`IOPSCopyPowerSourcesInfo`/`IOPSCopyPowerSourcesList`/`IOPSGetPowerSourceDescription`
  return `Unmanaged`/`CFTypeRef` values that need careful bridging** — get the
  `takeRetainedValue()`/`takeUnretainedValue()` split wrong (per Apple's docs: the info
  blob and the list are retained, the per-source description is unretained, borrowed from
  the list) and this leaks or double-frees. Antigravity should specifically verify no
  leak across a long-running sampling loop (Instruments, not just a visual check).
  `GPUUsageSampler`'s and `ThermalSensorReader`'s existing `IORegistryEntryCreateCFProperty`
  calls in this same directory are the closest precedent for the retain-counted idiom to
  follow.
- **Constant names**: `kIOPSCurrentCapacityKey`, `kIOPSTimeToEmptyKey`,
  `kIOPSTimeToFullChargeKey`, `kIOPSIsChargingKey`, `kIOPSPowerSourceStateKey`,
  `kIOPSACPowerValue` are all real `IOKit`/`IOPowerSources` framework constants, not
  invented here — Codex should confirm the exact import (`IOKit.ps`) and spelling against
  the SDK headers before use, the same verification `05`'s `sysctl` struct layout got.
- **The 20%/3-sample debounce constants are a judgment call, not a measured figure.** If
  Antigravity's manual testing (plug/unplug cycles) shows the window is too loose (still
  visibly jumpy) or too tight (stuck on "Calculating…" for multiple minutes under normal
  conditions), that's tuning feedback for this same ticket, not proof the design is wrong —
  report it in `## Comments` rather than silently picking different constants.
