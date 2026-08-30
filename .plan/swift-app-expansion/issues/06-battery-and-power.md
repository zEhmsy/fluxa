# 06 — Battery and power

Status: spec-pending
Owner: claude
Type: task
Spec: —
Blocked by: 03
Source: clean-room. Feature idea only. No upstream code read.

## Question

Battery state for the Mac itself, via `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription`:

- charge percentage
- time remaining (discharging) or time to full (charging)
- power source: battery / AC
- health: cycle count and maximum capacity, if cheaply available

Handle the desktop case: a Mac mini or Studio has no battery. The metric must be absent,
not zero — same rule the existing samplers follow for unavailable readings.

## Notes

**Time remaining is unreliable by nature.** macOS reports `-1` while it is still
calibrating after a state change, and the estimate swings for minutes after plugging or
unplugging. Show "Calculating…" rather than a number you don't trust, and never show a
figure that jumps between refreshes. This is the main design decision in the ticket.

Ties into ticket `03`: charge state is an enum, and time remaining is a duration —
neither fits the current `Kind`.

## Answer

_(pending)_

## Comments

_(none)_
