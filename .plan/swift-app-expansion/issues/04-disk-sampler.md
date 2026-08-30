# 04 — Disk sampler

Status: spec-pending
Owner: claude
Type: task
Spec: —
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

_(pending)_

## Comments

_(none)_
