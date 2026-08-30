# Spec 04 — Disk sampler

Ticket: `issues/04-disk-sampler.md`
Author: claude
Date: 2026-08-30

## Goal

Add disk space and throughput readings, following the sampler shape ticket `03`
generalized: new `SystemMetricID` cases, fed by new sampler types owned by
`SystemStatsSampler`.

## D1 — Four new `SystemMetricID` cases, not one

The ticket says "free/used space" as if it's one reading. It's better as two, because one
of them can be a real bounded metric and shouldn't be flattened into an unbounded one just
because it involves bytes:

| Case | Kind | What |
|---|---|---|
| `.diskUsedPercentage` | `.percentage` | `(total - available) / total * 100` on the boot volume |
| `.diskFreeSpace` | `.byteCount` | Absolute free bytes on the boot volume |
| `.diskReadRate` | `.byteRate` | Read throughput, delta since last sample |
| `.diskWriteRate` | `.byteRate` | Write throughput, delta since last sample |

`.diskUsedPercentage` reuses `.percentage`'s existing severity bands (75/90, same as
CPU/GPU/memory) — "disk almost full" is a legitimately urgent reading and this is the one
disk metric that gets a real meter with color, not the inert-fraction unbounded treatment.
A disk-specific severity curve (e.g. tighter than CPU's) is threshold-alert territory —
ticket `08`, not this one.

`.diskFreeSpace`, `.diskReadRate`, `.diskWriteRate` are `.byteCount`/`.byteRate` —
unbounded, `hasBoundedRange == false`, informational numbers with no meaningful meter.

Metadata for each (`title`/`shortLabel`/`symbolName`/`unavailableNote`), matching the
existing style in `Sources/FluxaCore/Models/SystemMetric.swift`:

```swift
case .diskUsedPercentage: return "Disk Used"      // title
case .diskFreeSpace:      return "Disk Free"
case .diskReadRate:       return "Disk Read"
case .diskWriteRate:      return "Disk Write"

case .diskUsedPercentage: return "DSK"            // shortLabel
case .diskFreeSpace:      return "FREE"           // 4 chars — the existing 3-char rule
                                                    // is a guideline from percentage/temp
                                                    // chips, not a hard limit; confirm it
                                                    // still fits the popover chip layout,
                                                    // shorten to "FRE" if not.
case .diskReadRate:       return "R"
case .diskWriteRate:      return "W"

case .diskUsedPercentage, .diskFreeSpace: return "internaldrive"   // symbolName
case .diskReadRate:                       return "arrow.down.circle"
case .diskWriteRate:                      return "arrow.up.circle"

case .diskUsedPercentage, .diskFreeSpace, .diskReadRate, .diskWriteRate:
    return "Not readable on this Mac."   // unavailableNote — same shape as existing cases
```

**No other file needs to know about these cases to make them selectable.**
`CustomizeSystemStatsSection.loadMetrics` already does
`SystemMetricID.allCases.filter { !temperatures.contains }` — new non-temperature cases
appear in the Customize picker automatically. The compact popover strip
(`SystemStatsStripView`) is opt-in via `settings.systemMetricIDs` (empty by default), so
nothing appears there uninvited either.

## D2 — One view needs a guard: `SystemStatsWindowView`

`SystemStatsWindowView.metricCard(_:)` (around line 103-140) renders **every** metric in
`stats.metrics` unconditionally — that's `SystemMetricID.allCases`-driven, not gated by
`settings.systemMetricIDs`. Today all six existing metrics are `.percentage`/`.temperature`
(bounded), so the capsule meter bar always meant something. The moment `.diskFreeSpace`
(or any `.byteRate`/`.byteCount` metric) exists, that bar renders at a permanent, inert 0
next to a real, non-zero number — visibly broken, not just imperfect.

This is the "first unbounded metric" view decision ticket `03` deferred to whichever
ticket shipped first. Fix, scoped to exactly this: in `metricCard(_:)`, wrap the
`GeometryReader` meter bar in a check on `metric.id.kind.hasBoundedRange`; when `false`,
omit the bar (the symbol, `shortLabel`, and `displayText` stay — only the capsule meter is
conditional). Do not touch `ControlDeckDashboardView`, `ControlDeckMetricsView`, or
`SystemStatsStripView` — they're already gated by the opt-in `systemMetricIDs` list, so
new disk metrics won't appear there until the owner adds them via Customize, and when they
do, `ControlDeckMetricPulse`'s bar has the same problem and needs the same guard **at that
point** — not preemptively here, since it's currently unreachable for these ids.

## D3 — Two sampler types, not one

Free/used space is a stateless snapshot (`URLResourceValues`, one call, no history
needed). Throughput needs a previous-tick baseline **and** wall-clock elapsed time — unlike
`CPUUsageSampler`, whose ticks are a self-normalizing ratio, bytes/sec needs an actual time
denominator. Mixing a snapshot reading and a delta-with-clock reading in one type conflates
two different lifecycles. Split them, both living in
`Sources/FluxaCore/Services/SystemStats/`, both owned by the `SystemStatsSampler` actor
exactly like the existing four:

### `DiskSpaceSampler` — stateless

```swift
struct DiskSpaceSampler {
    /// (usedPercentage, freeBytes), or nil for both if the boot volume can't be queried.
    func sample() -> (usedPercentage: Double?, freeBytes: Double?) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]) else { return (nil, nil) }

        guard let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity, total > 0
        else { return (nil, nil) }

        let free = Double(available)
        let usedPercentage = min(max((Double(total) - free) / Double(total) * 100, 0), 100)
        return (usedPercentage, free)
    }
}
```

`volumeAvailableCapacityForImportantUsage` is the definition of "free" used throughout —
document this choice in the doc comment, same as `MemorySampler`'s comment defends its
"active + wired + compressed" choice. It undercounts vs. raw `statfs` free space on
purpose: purgeable snapshots and caches macOS can reclaim don't count as "available" to the
user, matching what Finder's "Available" figure shows, not what `df` shows.

### `DiskThroughputSampler` — stateful, mutating

Follow `GPUUsageSampler`'s IOKit idiom exactly (linked framework, not `dlopen` — this data
is not the private-API situation `ThermalSensorReader` is in):

```swift
struct DiskThroughputSampler {
    private var previous: (bytesRead: UInt64, bytesWritten: UInt64, at: Date)?

    /// (readBytesPerSec, writeBytesPerSec), or nil for both on the first call or if no
    /// block storage driver is found.
    mutating func sample() -> (readRate: Double?, writeRate: Double?) {
        guard let current = Self.readCounters() else { return (nil, nil) }
        let now = Date()
        defer { previous = (current.bytesRead, current.bytesWritten, now) }
        guard let previous else { return (nil, nil) }

        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return (nil, nil) }

        let readDelta = Double(current.bytesRead &- previous.bytesRead)
        let writeDelta = Double(current.bytesWritten &- previous.bytesWritten)
        return (readDelta / elapsed, writeDelta / elapsed)
    }

    /// Sums "Bytes (Read)"/"Bytes (Write)" from the Statistics dictionary of every
    /// IOBlockStorageDriver — matches GPUUsageSampler's "enumerate what's there" idiom.
    ///
    /// This is a deliberate simplification: it sums across every attached block storage
    /// device, not just the boot volume. An external drive doing heavy I/O shows up in
    /// this number too. Isolating the boot volume's specific driver needs walking the BSD
    /// name through the IOMedia/IOPartitionScheme registry chain to its parent driver — a
    /// meaningfully bigger piece of work than this ticket's scope. If that precision turns
    /// out to matter, it's a follow-up ticket, not a silent gap here: this comment is that
    /// flag.
    private static func readCounters() -> (bytesRead: UInt64, bytesWritten: UInt64)? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWritten: UInt64 = 0
        var foundAny = false

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(
                service, "Statistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            if let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value {
                totalRead += read
                foundAny = true
            }
            if let written = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value {
                totalWritten += written
                foundAny = true
            }
        }

        return foundAny ? (totalRead, totalWritten) : nil
    }
}
```

## D4 — Wiring into `SystemStatsSampler`

Both new samplers are owned the same way the existing four are — as `actor` state,
`DiskThroughputSampler` as `var` (it's `mutating`), `DiskSpaceSampler` as `let`:

```swift
private var diskThroughput = DiskThroughputSampler()
private let diskSpace = DiskSpaceSampler()
```

In `sample()`, extend the `readings` dictionary:

```swift
let space = diskSpace.sample()
readings[.diskUsedPercentage] = space.usedPercentage
readings[.diskFreeSpace] = space.freeBytes

let throughput = diskThroughput.sample()
readings[.diskReadRate] = throughput.readRate
readings[.diskWriteRate] = throughput.writeRate
```

`prime()` (the CPU sampler's baseline warm-up call) should also warm `diskThroughput` the
same way, so the first *real* tick after launch already has a throughput number instead of
waiting a second full interval:

```swift
package func prime() {
    _ = cpu.sample()
    _ = diskThroughput.sample()
}
```

## Acceptance

1. Four new `SystemMetricID` cases exist with full metadata (title/shortLabel/symbolName/
   kind/unavailableNote).
2. `DiskSpaceSampler` and `DiskThroughputSampler` exist in
   `Sources/FluxaCore/Services/SystemStats/`, `package`-visible, wired into
   `SystemStatsSampler`.
3. `SystemStatsWindowView.metricCard(_:)` hides the meter bar (only) for
   `hasBoundedRange == false` metrics. No other view file changes.
4. A Mac with no accessible boot-volume stats (sandboxed test environment, permission
   denied) returns `nil` for all four — never a fabricated 0 or a crash.
5. `swift test`, `swift build`, `./build.sh` pass; no new strict-concurrency warnings; no
   `public` in `FluxaCore`.
6. Local build launched per `docs/agents/roles.md` for the owner to try — new disk metrics
   selectable in Customize → System.

## Out of scope

Per-disk breakdown (multiple volumes shown separately). Boot-volume-only throughput
isolation (see the comment in D3 — flagged, not solved). Disk read/write IOPS (only byte
throughput). Threshold alerts on any of these (`08`).

## Risks

- **`Int64(value)` in `SystemMetric.displayText`'s byte formatters traps on `NaN`/
  `infinity`.** `DiskSpaceSampler`/`DiskThroughputSampler` must only ever produce finite,
  non-negative `Double`s or `nil` — never propagate a divide-by-zero or overflow through.
  The `total > 0` guard and the `elapsed > 0` guard above exist specifically for this.
- **Counter wraparound**: `bytesRead &- previous.bytesRead` uses wrapping subtraction on
  purpose (matches `CPUUsageSampler`'s `&-`) so a counter reset doesn't crash — but a wrap
  produces a huge value, not a negative one, since these are `UInt64`. A dropped/reattached
  external disk between samples could produce one bogus spike reading. Antigravity should
  fuzz this specifically: is one wrong-but-finite spike acceptable, or does it need a
  sanity ceiling? Flagging for validation, not resolving here — this is exactly the same
  class of risk `05` (network) will also hit.
