# 08 — Threshold alerts on system metrics

Status: spec-pending
Owner: claude
Type: task
Spec: —
Blocked by: 03
Source: clean-room. Feature idea only. No upstream code read.

## Question

Notify the user when a metric crosses a configured limit — CPU above 90% sustained,
die temperature above a ceiling, boot volume below a few GB free.

This is the highest-leverage ticket in group A: the samplers, the history buffer and the
settings model all exist. It is mostly policy on top of data Fluxa already collects.

Design:

- Per-metric thresholds in `AppSettings`, with sensible defaults and an off switch.
- **Hysteresis and dwell time.** A CPU spike to 95% for one sample is noise. Fire only
  after the condition holds for N consecutive samples, and don't re-fire until the value
  has dropped meaningfully below the limit. Without this the feature is a notification
  spammer and users disable it within a day — that failure mode is the whole ticket.
- Delivery via `UNUserNotificationCenter`, which needs authorisation. Ask lazily, at the
  moment the user enables the first alert, never at launch.
- What happens when notifications are denied: the feature must degrade visibly, not fail
  silently. Fluxa has `PermissionsService`; follow whatever pattern it already sets.

## Notes

`SystemStatsHistory` and `SystemStatsInterval` already exist. The sampling interval is
user-configurable, so "N consecutive samples" means different wall-clock times at
different settings — express dwell in seconds, not in samples.

## Answer

_(pending)_

## Comments

_(none)_
