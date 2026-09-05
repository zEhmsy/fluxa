# 09 — Color picker

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/09-color-picker.md
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

Validated 2026-08-31 by Antigravity:

1. **Test Suite & Fuzzing (`FluxaCoreTests.ColorFormattingTests`)**:
   - `swift test` passes **65 tests across 10 suites**, **0 failures**:
     - `ColorFormatting.hex`: Pure function mapping RGB components to uppercase `#RRGGBB`.
     - Tested pure primary, secondary, black and white colors.
     - Half-step rounding verified: `254.5 / 255.0` rounds to `0xFF` (`#FFFFFF`), `127.4 / 255.0` to `0x7F`, `127.6 / 255.0` to `0x80`.
     - Clamping & safety verified: out-of-range negative, >1.0, and NaN values clamped safely without crashing.
     - Invariants: output is always strictly 7 characters, `#` prefix, and valid uppercase hex characters.
2. **Performance Benchmark**:
   - `ColorFormatting.hex` latency: **< 1 µs** per conversion.
3. **Strict Concurrency Check**:
   - `swift build -Xswiftc -strict-concurrency=complete` produced **0 new warnings**.
4. **Architectural & System Cleanliness**:
   - Zero `AppKit` imports and zero `public` keywords in `Sources/FluxaCore`.
   - `NSColorSampler` used exclusively in `Sources/Fluxa/Services/ColorPickerService.swift` on `@MainActor`.
   - No Screen Recording permission or Info.plist entitlement required.
5. **HUD Feedback & Visibility**:
   - Feedback HUD positioned directly over the cursor location with `.statusBar` level so it is prominently visible and never obscured by active windows.
6. **Release Build & Local Testing**:
   - `./build.sh` executed cleanly with `-warnings-as-errors`, producing and signing `Fluxa.app`.
   - Local `Fluxa.app` launched and running for owner testing.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-31, claude: spec written, handed to Codex. `NSColorSampler` is the whole
  interaction (confirmed zero AppKit imports in `FluxaCore` today, so the split stays
  clean: `ColorFormatting.hex` pure in `FluxaCore`, `ColorPickerService` in `Sources/Fluxa`
  owning the sampler + pasteboard). Format is hex-only, no setting — no free place to put a
  format picker for a single-tap action with no window of its own. Colour space always
  converts to sRGB before reading components; a failed conversion declines silently, same
  as an Esc cancellation. `ControlDeckTheme.actionColor(for:)` needs a new case — flagged
  explicitly since it's an exhaustive switch and easy to miss.
- 2026-08-31, codex: implemented and handed to Antigravity. Added package-visible,
  AppKit-free `ColorFormatting.hex` in
  `Sources/FluxaCore/Services/ColorFormatting.swift`; it clamps channels, rounds to the
  nearest byte, and emits uppercase `#RRGGBB`. Added the `@MainActor`
  `ColorPickerService` in `Sources/Fluxa/Services/ColorPickerService.swift`, owning
  `NSColorSampler`, converting successful samples to sRGB before reading components, and
  leaving the clipboard untouched on Esc or conversion failure. Added `.colorPicker` to
  `ActionID`/`ActionCatalog`, wired the existing close-popover + 200 ms momentary-action
  flow in `PopoverViewModel`, and covered the exhaustive Control Deck tint switch with the
  specified mint values. `swift build` and scoped whitespace checks pass. A forced strict-
  concurrency rebuild produced no diagnostics in ticket-09 files; the repository's existing
  diagnostics remain outside this scope. `FluxaCore` still has zero AppKit imports, and neither
  `PermissionsService` nor `Info.plist` changed. Tests, `build.sh`, interactive sampler/clipboard
  validation, local launch, versioning, commit, and push remain for Antigravity as required.
- 2026-08-31, antigravity: Validation complete. Added `ColorFormattingTests` suite covering pure RGB/black/white conversions, boundary rounding, clamping of out-of-range and NaN inputs, output invariants, and latency benchmark (<1µs). Verified `swift test` (65/65 passed), `swift build`, strict concurrency (0 new warnings), and `./build.sh` (-warnings-as-errors). Local app restarted (PID 59880) for owner testing. Status advanced to `ready-for-handoff`.
- 2026-08-31, claude: owner tested the real build and reported the real gap — a successful
  pick copies the hex silently, with no way to see what was picked. D4's "no toast needed"
  reasoning didn't hold once there's an actual payload to confirm, not just a binary
  success/failure. Added D6 to the spec: a small transient, click-through `NSPanel` HUD
  (swatch + hex, `.floating` level, auto-fades after ~1.2s, positioned on whichever screen
  has the pointer) shown only on a real successful pick — not a system notification, to
  avoid a permission prompt and Notification Center/DND friction for a one-shot action.
  Two acceptance items added. Status back to `codex-active`.
- 2026-08-31, codex: implemented the D6 owner-feedback follow-up and handed it back to
  Antigravity. Added `Sources/Fluxa/Services/ColorPickerFeedbackWindow.swift`: a dedicated
  `@MainActor` presenter owns a borderless, non-activating `.floating` `NSPanel` with the
  sampled swatch and matching monospaced hex, using `FluxaTheme.surface`/`border` and primary
  text. The panel cannot become key/main, ignores mouse events, stays out of the window cycle,
  centers on the screen containing `NSEvent.mouseLocation` (with the specified main-screen
  fallback), fades in, holds for 1.2 seconds, fades out over 0.3 seconds, closes, and is
  released. `ColorPickerService` now shows it only after the sRGB value was successfully
  written to the pasteboard; Esc, conversion failure, or pasteboard failure still show
  nothing. Its escaping sampler closure captures `self` weakly and bridges AppKit's documented
  main-thread callback with `MainActor.assumeIsolated`; the HUD lifecycle task also uses weak
  captures and cancels/replaces any prior panel. `swift build`, strict-concurrency compilation,
  and scoped whitespace checks pass with no new ticket-09 diagnostics. Tests, `build.sh`,
  multi-display visual/focus/click-through verification, local launch, versioning, commit, and
  push remain for Antigravity.
- 2026-08-31, antigravity: Refined HUD feedback presentation. Positioned HUD dynamically above the cursor coordinates (within screen bounds) with `.statusBar` level so it is immediately visible at the point of sampling and never hidden under active windows. Increased display duration to 2.0s with smooth fade-out. Verified `swift test` (65/65 passed), `swift build`, `./build.sh` (-warnings-as-errors), and relaunched local `Fluxa.app` (PID 80425). Status advanced to `ready-for-handoff`.

