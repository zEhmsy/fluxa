# Spec 05 — Network sampler

Ticket: `issues/05-network-sampler.md`
Author: claude
Date: 2026-08-30

## Goal

Upload/download throughput as two new `SystemMetricID` cases, following the pattern
`04` established: unbounded `.byteRate` metrics, a stateful sampler owned by
`SystemStatsSampler`.

## D1 — Deviation from the ticket: `sysctl(NET_RT_IFLIST2)`, not `getifaddrs`

The ticket names `getifaddrs` with `if_data.ifi_ibytes`/`ifi_obytes`. Checked against the
SDK headers (`<net/if_var.h>`) before writing this:

```c
struct if_data {           // what getifaddrs's ifa_data points to for AF_LINK entries
    u_int32_t ifi_ibytes;  // 32-bit
    u_int32_t ifi_obytes;  // 32-bit
};
```

A 32-bit byte counter wraps at 4 GiB. A single sustained transfer on Gigabit Ethernet
(~120 MB/s) wraps it in under 40 seconds — this is not an edge case on modern hardware,
it's routine. The ticket's own "counter wraparound" risk section is really flagging a
near-certainty with `getifaddrs`, not a rare fault.

Use `sysctl` with `NET_RT_IFLIST2` instead (`<sys/socket.h>`, `<net/if.h>` — also checked
against the SDK):

```c
struct if_msghdr2 {
    int ifm_flags;                 // IFF_UP, IFF_LOOPBACK, etc.
    u_short ifm_index;             // resolve to a name via if_indextoname
    struct if_data64 ifm_data;     // 64-bit ifi_ibytes / ifi_obytes
};
```

**Same "no entitlement needed" property the ticket requires** — this is the standard
`netstat -ib` mechanism, a read-only informational sysctl. 64-bit counters make
wraparound require multiple centuries of continuous max-throughput transfer: the risk the
ticket asked to design around is eliminated by this substitution, not mitigated. Note the
deviation explicitly in `## Comments` when this ticket resolves, since it departs from the
API the ticket named.

## D2 — Interface filtering: allowlist, not blocklist

The ticket lists what to exclude (`lo0`, `utun*`, `bridge*`, `awdl0`). A blocklist is
fragile against interface types macOS adds later — missing one silently double-counts
again, the exact failure mode the ticket is trying to avoid.

**Allowlist instead**: an interface counts if `ifm_flags & IFF_UP != 0`, `ifm_flags &
IFF_LOOPBACK == 0`, and its resolved name (via `if_indextoname(ifm_index, buf)`) starts
with `"en"` — Wi-Fi and every Ethernet/Thunderbolt-Ethernet adapter on macOS is `enN`.
Everything else (`utun*`, `ipsec*`, `ppp*`, `bridge*`, `awdl0`, `llw0`, `gif*`, `stf*`,
`lo0`) is excluded by construction, without naming each one.

**Known gap, stated deliberately**: an unusual USB-Ethernet dongle whose driver doesn't
present as `enN` reads as no traffic, not wrong traffic. Matches the "better no number
than a fabricated one" convention `CPUUsageSampler`/`GPUUsageSampler` already use for
missing data — an omission, not a silent lie.

**Sum across all matching interfaces**, not just one. A Mac can have Wi-Fi and Ethernet
both `IFF_UP` simultaneously (rare but real — a laptop docked with Ethernet while Wi-Fi
stays associated). Reporting only the first match would silently drop half the traffic.

## D3 — `NetworkThroughputSampler`, stateful, keyed by interface name

Unlike disk (one throughput number per direction, ticket `04`), network needs **per-
interface** baselines: interfaces can appear and disappear between samples (dock/undock,
Wi-Fi toggle), and if_indextoname's index can be reused after an interface is removed and
a different one added — tracking by name, not index, avoids attributing a stale baseline
to a new, unrelated interface.

```swift
struct NetworkThroughputSampler {
    private struct Baseline {
        let bytesIn: UInt64
        let bytesOut: UInt64
        let at: Date
    }

    private var previous: [String: Baseline] = [:]

    /// (downloadBytesPerSec, uploadBytesPerSec), or nil for both on the first call or if
    /// no counted interface is up.
    mutating func sample() -> (downloadRate: Double?, uploadRate: Double?) {
        let current = Self.readCounters()  // [String: (bytesIn, bytesOut)], allowlist-filtered
        guard !current.isEmpty else {
            previous = [:]
            return (nil, nil)
        }

        let now = Date()
        var totalDown = 0.0
        var totalUp = 0.0
        var anyDelta = false

        for (name, counters) in current {
            defer { previous[name] = Baseline(bytesIn: counters.bytesIn, bytesOut: counters.bytesOut, at: now) }
            guard let baseline = previous[name] else { continue }   // this interface just appeared

            let elapsed = now.timeIntervalSince(baseline.at)
            guard elapsed > 0 else { continue }

            totalDown += Double(counters.bytesIn &- baseline.bytesIn) / elapsed
            totalUp += Double(counters.bytesOut &- baseline.bytesOut) / elapsed
            anyDelta = true
        }

        // Drop baselines for interfaces that vanished, so the dict doesn't grow forever
        // across a long-running app lifetime with interfaces coming and going.
        previous = previous.filter { current[$0.key] != nil }

        return anyDelta ? (totalDown, totalUp) : (nil, nil)
    }

    private static func readCounters() -> [String: (bytesIn: UInt64, bytesOut: UInt64)] {
        // sysctl(CTL_NET, PF_ROUTE, 0, AF_UNSPEC, NET_RT_IFLIST2, 0) -> size, then buffer.
        // Walk the returned if_msghdr2 records (ifm_type == RTM_IFINFO2), filter per D2,
        // resolve name via if_indextoname(ifm_index, ...), collect ifm_data.ifi_ibytes /
        // ifi_obytes keyed by name.
    }
}
```

The sketch of `readCounters()` mirrors the two-call `sysctl` idiom (call once with a null
buffer to get the required size, allocate, call again to fill it) — standard for this API,
not specific to this ticket; implement it directly, no need to design it further here.

## D4 — Wiring

Two new `SystemMetricID` cases, both `.byteRate` (unbounded, `hasBoundedRange == false`,
same `SystemStatsWindowView` guard from `04` already covers them — no further view work):

```swift
case .networkDownloadRate   // title: "Download", shortLabel: "DN", symbolName: "arrow.down"
case .networkUploadRate     // title: "Upload",   shortLabel: "UP", symbolName: "arrow.up"
```

`SystemStatsSampler` owns `private var network = NetworkThroughputSampler()`, extends
`sample()`:

```swift
let net = network.sample()
readings[.networkDownloadRate] = net.downloadRate
readings[.networkUploadRate] = net.uploadRate
```

`prime()` warms it the same way `04` warmed disk throughput:

```swift
package func prime() {
    _ = cpu.sample()
    _ = diskThroughput.sample()
    _ = network.sample()
}
```

## Acceptance

1. Two new `SystemMetricID` cases, full metadata, `.byteRate`.
2. `NetworkThroughputSampler` in `Sources/FluxaCore/Services/SystemStats/`, `package`,
   wired into `SystemStatsSampler` and `prime()`.
3. Uses `sysctl(NET_RT_IFLIST2)`, not `getifaddrs` — 64-bit counters.
4. Interface selection is the `en*` + `IFF_UP` + `!IFF_LOOPBACK` allowlist, summed across
   all matches, keyed by name for cross-tick baselines.
5. An interface disappearing between samples doesn't produce a spike or a crash; its
   baseline is dropped, not diffed against a now-unrelated replacement.
6. `swift test`, `swift build`, `./build.sh` pass; no new strict-concurrency warnings; no
   `public` in `FluxaCore`.
7. Local build launched per `docs/agents/roles.md`.

## Out of scope

Per-interface breakdown in the UI (Wi-Fi vs. Ethernet shown separately) — this reports one
combined download/upload number, same simplification `04` made for disk. Threshold alerts
(`08`).

## Risks

- **`sysctl` buffer sizing race**: the two-call idiom (size query, then fill) can race if
  an interface is added between the two calls, making the second call's buffer too small.
  Standard handling: if the fill call reports the buffer was too small, retry once with a
  freshly queried size rather than failing outright.
- Same finite/non-negative `Double` precondition as `04`'s risk note — `SystemMetric`'s
  byte-rate formatter traps on `NaN`/`infinity`, so a zero-or-negative `elapsed` must
  never reach the division (already guarded above, but call out for Antigravity to fuzz).
