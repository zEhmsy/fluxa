# 05 — Network sampler

Status: spec-pending
Owner: claude
Type: task
Spec: —
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

_(pending)_

## Comments

_(none)_
