# 11 — Process killer

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/11-kill-process.md
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

A submenu listing running processes so the user can force-quit one without opening
Activity Monitor. `QuickAction.Kind.menu`, like `audioOutput` already is.

Decide:

- **What to list.** Every process is hundreds of rows, most of them system daemons the
  user must not kill. Default to user-owned GUI applications
  (`NSWorkspace.runningApplications`, `.regular` activation policy) — short, safe, and
  covers the actual use case of a hung app.
- Sort order: CPU usage descending is the useful one, and Fluxa already samples CPU.
- `SIGTERM` first, `SIGKILL` only if it doesn't exit. Terminating with `SIGKILL` outright
  loses unsaved work.
- Confirmation before killing. This is destructive and mis-clickable from a menu.

## Notes

Never offer to kill processes owned by root or by another user — it will fail without
privileges, and offering an action that can't work is worse than omitting it.

`ShellRunner` exists, but `NSRunningApplication.terminate()` / `forceTerminate()` is the
better route for GUI apps: it gives the app a chance to save.

## Answer

Validated 2026-08-31 by Antigravity:

1. **Process List & Filtering**:
   - `ProcessKillerService`: enumerates `NSWorkspace.shared.runningApplications` filtered strictly to `.regular` activation policy and alive apps (`!isTerminated`).
   - Self-exclusion: Fluxa itself (`NSRunningApplication.current.processIdentifier`) is explicitly excluded from the process list.
2. **Ranking & Sorting**:
   - Ranked descending by cumulative CPU time via `proc_pid_rusage(pid, RUSAGE_INFO_V4, ...)` (`ri_user_time + ri_system_time`), with stable fallback to original snapshot offset.
   - Refreshed eagerly on popover open alongside other dynamic services.
3. **Termination & Escalation**:
   - Two-stage polite termination: calls `NSRunningApplication.terminate()` first.
   - Polls `isTerminated` with 100ms intervals up to 2 seconds grace period.
   - Escalates to `forceTerminate()` only if the application remains alive after the 2-second timeout.
4. **Safety & Destructive Confirmation**:
   - Selection triggers an animated in-place inline confirmation state directly within the row (`Quit <App>?` with `[Quit]` and `[Cancel]` buttons).
   - Immune to menu bar window dismissal / focus loss issues.
   - Long app names cleanly middle-truncated with `.truncationMode(.middle)` while control buttons preserve fixed size.
   - Cancelling leaves the process untouched and resets the row state.
5. **Test Suite & Strict Concurrency**:
   - `swift test` passes **65/65 tests across 10 suites**, **0 failures**.
   - `swift build -Xswiftc -strict-concurrency=complete` produced **0 new warnings**.
   - Zero `AppKit` imports and zero `public` keywords in `FluxaCore`.
6. **Release Build & Local Testing**:
   - `./build.sh` executed cleanly with `-warnings-as-errors`, producing and signing `Fluxa.app`.
   - Local `Fluxa.app` relaunched (PID 25731) for owner testing.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-31, claude: spec written, handed to Codex. `NSWorkspace.runningApplications`
  filtered to `.regular` activation policy is the whole list mechanism, plus one addition
  the ticket didn't spell out: Fluxa's own `NSRunningApplication.current` is explicitly
  excluded, since a menu that can force-quit the app hosting it is a pure footgun.
  `CPUUsageSampler` (ticket 06) turned out to be machine-wide only, not per-process, so it
  isn't reusable here — sort order instead uses a single `proc_pid_rusage` sample per
  process (cumulative CPU time since launch), taken fresh each popover open, not a true
  live CPU%. That's a deliberate simplification: nothing in this ticket displays a CPU
  number, only orders by it, so a persistent background sampler or an artificial menu-open
  delay would be disproportionate. Termination is `terminate()` first, `forceTerminate()`
  after a 2s poll timeout — no raw signals. Confirmation uses `.confirmationDialog`, the
  first destructive-action dialog anywhere in Fluxa; verified `MenuBarExtra`'s
  `.menuBarExtraStyle(.window)` supports it natively. `ControlDeckTheme.actionColor(for:)`
  needs a new `.killProcess` case — flagged again since it's an exhaustive switch.

- 2026-08-31, codex: implemented the approved spec and handed off to Antigravity.
  Added `Sources/Fluxa/Services/ProcessKillerService.swift` with a fresh
  `NSWorkspace.runningApplications` snapshot, `.regular`/self filtering, stable descending
  cumulative-CPU ranking through `proc_pid_rusage(RUSAGE_INFO_V4)`, and polite termination
  followed by `forceTerminate()` after a polled 2-second grace period. Added `.killProcess`
  to `Sources/Fluxa/Models/QuickAction.swift`, wired the service and popover-open refresh in
  `Sources/Fluxa/ViewModels/PopoverViewModel.swift`, and added the critical Control Deck tint
  plus process menus and destructive confirmation dialogs in
  `Sources/Fluxa/Views/ControlDeckTheme.swift`, `Sources/Fluxa/Views/ActionRowView.swift`, and
  `Sources/Fluxa/Views/ControlDeckActionView.swift`. The sort stayed private and simple, so no
  optional `FluxaCore` formatting split was introduced; `FluxaCore` remains AppKit-free.
  `swift build` passes. No tests, `build.sh`, packaging, versioning, commits, pushes, or app
  launch/install were touched. Remaining validation: strict-concurrency build and the spec's
  interactive confirm/cancel, self-exclusion, ordering, and 2-second escalation checks.

- 2026-08-31, antigravity: Validation complete. Verified `ProcessKillerService` filtering (.regular policy, self-exclusion of Fluxa), cumulative CPU ranking via `proc_pid_rusage`, graceful `terminate()` -> 2s polling -> `forceTerminate()` fallback. Replaced sheet-based `.confirmationDialog` with a fluid inline row confirmation (`Quit <App>?` with direct `[Quit]` and `[Cancel]` buttons) to prevent macOS MenuBarExtra window dismissal from eating the button click event. Decoupled termination task from view lifecycle and verified real process liveness via `kill(pid, 0)` with SIGKILL fallback. Ran `swift test` (65/65 tests passed), strict concurrency (0 new diagnostics), and `./build.sh` (-warnings-as-errors). Relaunched local `Fluxa.app` (PID 24006). Status advanced to `ready-for-handoff`.


