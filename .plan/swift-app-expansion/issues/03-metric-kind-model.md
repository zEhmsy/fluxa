# 03 — Extend the metric model beyond percentage and temperature

Status: spec-pending
Owner: claude
Type: task
Spec: —
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

_(pending)_

## Comments

_(none)_
