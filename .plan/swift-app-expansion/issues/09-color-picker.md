# 09 — Color picker

Status: spec-pending
Owner: claude
Type: task
Spec: —
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

A one-shot quick action: the cursor becomes a picker, the user clicks a pixel anywhere on
screen, the colour lands on the clipboard.

Fits `QuickAction.Kind.momentaryButton` or a plain action. Add a `QuickAction.ActionID`
case and a service beside the existing ones.

Decide:

- Format on copy: hex `#RRGGBB`, or a user choice including `rgb()` and NSColor literal.
  One default, configurable only if it's free.
- Whether to show a magnified loupe while picking. `NSColorSampler` (macOS 10.15+) gives
  the whole interaction for almost nothing — **check it before building anything custom**;
  a hand-rolled loupe is a week of work to reproduce a system control.
- Colour space. A screen pixel is in the display's profile, not sRGB. Converting or not
  changes the hex the user gets. State the choice.

## Notes

`NSColorSampler` requires no Screen Recording permission. A custom implementation using
`CGWindowListCreateImage` **does**, as of macOS 15 with recurring prompts. That alone
should decide the approach.

## Answer

_(pending)_

## Comments

_(none)_
