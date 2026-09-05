# 11 — Process killer

## Goal

A `.menu`-style quick action, next to `audioOutput` and `bluetoothAudio` in shape: opening it
lists the user's running GUI apps, CPU-heaviest first, and picking one asks for confirmation
before terminating it. No Activity Monitor detour for the common case of "this app is hung
or eating my CPU, get rid of it."

## Where this lives

- `Sources/FluxaCore/Services/ProcessListFormatting.swift` — pure, AppKit-free: sorting a
  list of `(name, cpuTime)` pairs descending, nothing else. Small enough that it may not
  even need its own file; Codex's call whether this earns a `FluxaCore` split at all or
  just stays inline in the service below as a `private` sort. Only worth splitting out if
  it ends up non-trivial enough to unit test on its own.
- `Sources/Fluxa/Services/ProcessKillerService.swift` — `@MainActor`, owns
  `NSWorkspace.runningApplications`, `proc_pid_rusage`, and
  `NSRunningApplication.terminate()`/`.forceTerminate()`. All AppKit/libproc-touching code
  stays here, mirroring `AudioOutputService`'s split.
- `Sources/Fluxa/Views/ActionRowView.swift` and `Sources/Fluxa/Views/ControlDeckActionView.swift`
  — both already hand-roll `audioDeviceMenu`/`bluetoothMenu`-shaped `Menu { ForEach { Button } }`
  blocks per row; this ticket adds a third one, `processKillerMenu`, in both files. They are
  not shared today (each view duplicates the audio menu independently), so don't introduce a
  cross-file abstraction now just for this ticket — follow the existing duplication pattern.

## Decisions

### A — Process list scope: `NSWorkspace.runningApplications`, `.regular` policy, self excluded

`NSWorkspace.runningApplications` filtered to `activationPolicy == .regular` is the ticket's
own recommendation and is taken as-is: it's inherently scoped to the current user's GUI
session (not root or another user's processes — `NSWorkspace` doesn't surface those), and
`.regular` excludes background agents/daemons/menu-bar-only apps, leaving just the apps a
user would recognize in the Dock or Cmd-Tab.

One addition the ticket doesn't spell out: **exclude Fluxa itself.** Fluxa's own
`NSRunningApplication` (`NSRunningApplication.current`) must never appear in the list — a
menu action that can force-quit the app hosting the menu is a footgun with no upside, since
quitting Fluxa is already one click away in its own menu.

### B — Sort order: single-sample cumulative CPU time via `proc_pid_rusage`, not a delta sampler

The ticket says "CPU usage descending... Fluxa already samples CPU," pointing at
`CPUUsageSampler`. That sampler is machine-wide only (`host_statistics(HOST_CPU_LOAD_INFO)`,
delta between two consecutive calls) — there's no per-process reuse available, so this
ticket needs its own mechanism, not a call into `06`'s existing sampler.

Two ways to get a per-process number:

1. **True instantaneous CPU%**, matching Activity Monitor's column — needs two samples of
   `proc_pid_rusage`'s cumulative CPU time per process, seconds apart, and a background timer
   or an artificial delay when the menu opens.
2. **Single-sample cumulative CPU time since launch** (`proc_pid_rusage(RUSAGE_INFO_V4)` →
   `ri_user_time + ri_system_time`, one call per process, taken fresh each time the menu
   opens) — not the same number Activity Monitor shows, but the ranking it produces is
   still useful: a process that has burned more total CPU tends to be the one worth
   surfacing first, and a long-hung app in particular accumulates cumulative time fast.

Going with **(2)**. It needs no persistent background sampler and no artificial delay before
the menu is usable, both of which would be disproportionate for a list that only needs a
reasonable default order, not a precise metric — nothing in this ticket displays a CPU
number to the user, it's sort order only. This is a deliberate simplification, not an
oversight; if a future ticket wants a real live CPU% column, that's new scope with its own
sampler.

Sampled fresh every time the menu is opened (same eager-refresh-on-popover-open convention
`PopoverViewModel` already uses for `audioOutput`/`bluetoothAudio`/`peripheralBattery`/
`agentUsage`), not cached, so the order reflects current reality each time.

### C — Termination: `terminate()` first, `forceTerminate()` on a timeout

Per the ticket's own note, `NSRunningApplication.terminate()` (polite `AppleEvent`-based quit,
lets the target app save state) is tried first. If the app hasn't exited within a short
timeout (2s), `forceTerminate()` (`SIGKILL`-equivalent) is used as the escalation — this is
the AppKit-level equivalent of the ticket's "SIGTERM first, SIGKILL only if it doesn't exit."
No raw signals are sent; both calls go through `NSRunningApplication`.

The 2s timeout is polled via `isTerminated`, not a fixed blocking sleep — if the app exits
in 200ms, the flow completes in 200ms, not 2s.

### D — Confirmation: `.confirmationDialog`, first of its kind in this app

Nothing in `Sources/Fluxa/` uses `.confirmationDialog`, `.alert(`, or `NSAlert` today — this
is the first destructive-action confirmation UI in Fluxa. `MenuBarExtra { }
.menuBarExtraStyle(.window)` confirms the popover is a real SwiftUI-window-backed panel, so
native `.confirmationDialog` works without any special handling.

Selecting a process from the menu doesn't kill it immediately — it sets a local
`@State private var pendingKill: RunningProcessInfo?` on the row (mirroring the existing
`@State private var isHovering = false` precedent already on both `ActionRowView` and
`ControlDeckActionView`), which drives a `.confirmationDialog(pendingKill.map { "Quit \($0.name)?" } ?? "", ...)`
attached to the row. Confirming calls into `ProcessKillerService`; cancelling clears
`pendingKill` and does nothing. Because this state is per-row and local, it doesn't need to
live in `PopoverViewModel` or survive the popover closing.

### E — Wiring

- New `ActionID.killProcess` case.
- `ActionCatalog` entry: icon `"xmark.circle"`, no `activeIcon` (nothing to reflect — this
  is a `.menu`, not a toggle), `tint: FluxaTheme.red` (already used by `lockKeyboard`; tints
  are reused across actions elsewhere in this catalog, not exclusive per-action), subtitle
  static text along the lines of "Force-quit a running app," `controlStyle: .menu`.
- `ControlDeckTheme.actionColor(for:)` needs a new `.killProcess` case — this is an
  exhaustive switch and a missing case is a compile error, not a silent gap, but flagging it
  explicitly since every prior ticket has needed the same reminder. `critical` is the natural
  palette color there, matching the destructive intent.
- `PopoverViewModel` gets a `processKiller: ProcessKillerService` alongside the other
  services, with a `.refresh()` call added to the existing eager-refresh-on-popover-open
  batch (~line 335-350) so the list is current the moment the popover opens.
- `ActionRowView.processKillerMenu` and `ControlDeckActionView.processKillerMenu`: both
  mirror `audioDeviceMenu`'s `Menu { ForEach { Button { ... } } } label: { menuGlyph(...) }`
  shape. Each row's process button sets `pendingKill` instead of calling the service
  directly; the `.confirmationDialog` modifier lives on the row's outer view, next to
  where `isHovering`'s `.onHover` already sits.
- If the list is empty (no eligible processes — should only happen if Fluxa is somehow the
  only `.regular` app running), disable the menu the same way `audioDeviceMenu` disables on
  `outputDevices.isEmpty`.

## Tests

- `ProcessListFormatting` (if split out per the "Where this lives" note): sorting a list of
  `(name: String, cpuTime: Double)` pairs descending by `cpuTime`; stable order for ties;
  empty-list handling.
- Everything else in this ticket — `NSWorkspace`, `proc_pid_rusage`, `NSRunningApplication`
  termination — is AppKit/libproc-backed and not independently unit-testable in
  `FluxaCoreTests`; validated instead by Antigravity's interactive checklist (launch a
  disposable test app, confirm it appears in the list, confirm it terminates on confirm,
  confirm Fluxa itself never appears, confirm cancel leaves it running).

## Acceptance

1. Opening the process-killer menu shows only `.regular`-activation-policy apps, CPU-heaviest
   first, refreshed each time the popover opens.
2. Fluxa itself never appears in the list under any circumstance.
3. Picking a process shows a confirmation dialog naming that process; nothing is killed until
   confirmed.
4. Cancelling the dialog leaves the target process untouched and clears the pending state.
5. Confirming calls `terminate()`; if the process hasn't exited within 2 seconds,
   `forceTerminate()` is called as escalation.
6. `ControlDeckTheme.actionColor(for:)` and `ActionCatalog` both have a `.killProcess` entry;
   the project builds clean (the exhaustive switch would otherwise fail to compile).
7. An empty eligible-process list disables the menu rather than showing an empty/broken one.
8. `FluxaCore` still has zero AppKit imports after this ticket.

## Out of scope

- A live, Activity-Monitor-accurate CPU% column — this ticket's sort order is a one-shot
  cumulative-time ranking, not a displayed metric. A real percentage would need its own
  background sampler and is new scope.
- Killing non-`.regular` processes (daemons, background agents, system processes) — never
  offered, per the ticket's own root/other-user safety note; `.regular` filtering is the
  whole mechanism for that, no separate permission check is added.
- Any "recently force-quit" history or undo — once confirmed, it's gone, same as Activity
  Monitor.
