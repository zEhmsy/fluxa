# 05 — Network sampler

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/05-network-sampler.md
Blocked by: 03
Source: clean-room. Feature idea only. No upstream code read.

## Question

Upload and download throughput, as a delta between ticks. `getifaddrs` with
`if_data.ifi_ibytes` / `ifi_obytes` is the standard route and needs no entitlement.

Decide:

- **Which interfaces count.** Summing everything double-counts: `lo0` loopback, `utun*`
  VPN tunnels carrying traffic already counted on the physical interface, `bridge*` and
  `awdl0`. Getting this wrong makes the number confidently wrong, which is worse than absent.
- **Counter wraparound.** `ifi_ibytes` is 32-bit on some interfaces and wraps. A naive
  delta produces a huge negative spike.
- **Interface changes mid-session** — Wi-Fi to Ethernet, VPN up/down. Counters reset;
  don't report the reset as a burst.

## Notes

No entitlement or permission is required for `getifaddrs`. If a design needs one,
it is the wrong design.

## Answer

Implemented and Validated 2026-08-30 (Codex + Antigravity):

1. **Implementation Summary**:
   - Implemented `NetworkThroughputSampler` using `sysctl(NET_RT_IFLIST2)` reading `if_data64` (64-bit byte counters).
   - Filtered active physical adapters via allowlist: `en*` interface prefix + `IFF_UP` + `!IFF_LOOPBACK`.
   - Tracked baseline byte counts keyed per interface name; dropped removed interfaces from baseline cache; handled buffer resizing race with one retry pass.
   - Added `SystemMetricID.networkDownloadRate` ("DN") and `SystemMetricID.networkUploadRate` ("UP") with `.byteRate` kind, mapped in `SystemMetric.swift`, `ControlDeckTheme.swift`, and `SystemStatsWindowView.swift`.
   - Wired `NetworkThroughputSampler` into `SystemStatsSampler` (sample + prime).

2. **Test Suite & Verification (`FluxaCoreTests.NetworkSamplerTests`)**:
   - `swift test` passes **37 tests across 5 suites** (`NetworkSamplers`, `DiskSamplers`, `FluxaCore`, `SystemMetricKindModel`, `URLCleaner`), **0 failures**:
     - Baseline behavior: first sample returns `(nil, nil)`; subsequent ticks sample non-negative finite download/upload rates.
     - Actor integration: `SystemStatsSampler.sample()` includes network metrics; `prime()` warms baselines.
     - Formatting & display: `.networkDownloadRate` and `.networkUploadRate` format with binary `/s` unit scaling (`KB/s`, `MB/s`), inert `0.0` fraction, and `.normal` severity.
3. **Performance Benchmarks**:
   - Network throughput sampling latency: ~**0.30 ms** per sample pass across active network interfaces.
4. **Strict Concurrency Check**:
   - `swift build -Xswiftc -strict-concurrency=complete` produced **0 new warnings**.
5. **Release Build & Local Testing**:
   - `./build.sh` passed cleanly with `-warnings-as-errors`, creating and signing `Fluxa.app`.
   - Local `Fluxa.app` launched and active.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-30, claude — Spec written. **Deliberate deviation from the ticket's suggested
  API**: `getifaddrs`'s `if_data.ifi_ibytes` is 32-bit — verified against SDK headers —
  and wraps in well under a minute on Gigabit Ethernet under load, so the ticket's
  "counter wraparound" risk is closer to routine than edge case with that API. Used
  `sysctl(NET_RT_IFLIST2)` instead (`if_data64`, 64-bit counters, same no-entitlement
  property, same mechanism `netstat -ib` uses) — this eliminates the wraparound problem
  rather than working around it.
  Interface selection is an allowlist (`en*` name prefix + `IFF_UP` + not loopback), not
  the ticket's blocklist — safer against future macOS interface types the blocklist
  wouldn't know to exclude. Sums across all matching interfaces (Wi-Fi + Ethernet can both
  be up at once). Baselines tracked by interface name, not index, since index can be
  reused after an interface is removed and replaced.
- 2026-08-30, codex/antigravity — Implemented D1–D4 and completed end-to-end validation. Added `Sources/FluxaCore/Services/SystemStats/NetworkThroughputSampler.swift`, updated `SystemMetric.swift`, `ControlDeckTheme.swift`, `SystemStatsWindowView.swift`, and `SystemStatsSampler.swift`. Added `Tests/FluxaCoreTests/NetworkSamplerTests.swift`. Verified all 37 tests pass, 0 concurrency warnings, release build passed with `-warnings-as-errors`, and re-launched local `Fluxa.app`. Status advanced to `ready-for-handoff`.

