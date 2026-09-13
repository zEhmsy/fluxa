# 18 — Menu bar item disappears: Control Center applied another app's denial to Fluxa

Status: ready-for-handoff
Owner: antigravity
Type: bug
Spec: specs/18-menubar-item-cannot-return.md
Blocked by: —
Source: Owner report, 2026-09-05 — the menu bar icon stopped appearing and no reinstall brought it
back. Reopened the same day: the first diagnosis and its fix were both wrong, and the icon is still
missing on a build that carries the fix. Corrected root cause below, measured on the owner's machine.

## Question

Fluxa is a menu bar app and nothing else: `MenuBarExtra` is its only scene, so its icon is the only
way to reach any of it. Cmd-dragging that icon out of the menu bar is a standard macOS gesture, and
macOS records the result in the **app's own** preferences domain:

```
$ defaults read com.giuseppe.fluxa | grep NSStatusItem
"NSStatusItem VisibleCC Item-0" = 0;
```

Every later launch honours that flag. The process starts, runs, and draws nothing. There is no menu,
no window and no Dock icon to reach — the app is running and completely unreachable.

Reinstalling does not help, and this is the part that cost the owner the most time: the flag lives
in `~/Library/Preferences/com.giuseppe.fluxa.plist`, not in the bundle, so deleting
`/Applications/Fluxa.app`, replacing it, or resetting Control Center all leave it exactly as it was.
The only recoveries are `defaults delete`, which no user will find, or wiping all preferences, which
throws away every setting to fix a boolean.

This is not a regression from any recent ticket. It has been reachable since Fluxa's first build.

## Decide

- **Whether the icon should be hideable at all.** For an app with a second surface — a Dock icon, a
  main window, a login-item preference — a hideable menu bar item is a feature. For this app it is a
  way to uninstall the UI while leaving the process running. See the fix.
- **Whether to also clear the stale flag on launch.** Rejected: writing another app's — or macOS's —
  status item bookkeeping to undo a user gesture is worse than declining the gesture in the first
  place, and it would fight the system every launch.

## Correction — the flag is a symptom, not the cause

Everything above describes the flag accurately and draws the wrong conclusion from it. Build 19
carries `isInserted: .constant(true)`; the owner still sees nothing, so the fix has to be treated as
disproved rather than pending confirmation.

What the flag actually is: Fluxa **rewrites it to `0` itself, on every launch**, including launches
started with the key deleted. It is the outcome the app produces, not the input it reads.

Measurements taken on the owner's machine, each with its control:

- **The app does create a status item.** The unified log shows Fluxa owning an
  `NSSceneStatusItem` under a `com.apple.controlcenter` scene. An earlier claim that no item existed
  came from a `CGWindowListCopyWindowInfo` probe; that probe is worthless here, because macOS
  attributes *every* menu bar item window to Control Center. The Accessibility API is the reliable
  instrument (`AXExtrasMenuBar`, children at `y=4.5` visible, `y=981` parked off-screen).
- **The item is re-inserted about every 10.5 s.** `NSStatusItemChangeVisibilityAction` arrives at
  15:16:09.5, 15:16:20.1, 15:16:30.5, 15:16:41.1, 15:16:51.6, 15:17:02.2, and on. Twenty events in
  three minutes.
- **Control:** two throwaway `MenuBarExtra` apps, one plain and one with
  `isInserted: .constant(true)`, both get a visible item immediately (`x=1093` and `x=1060`, both at
  `y=4.5`) and log **zero** such events over the same three minutes. So the environment is fine,
  `isInserted:` is fine, and the churn is Fluxa's.
- **Not the strip width, not the notch.** Emptying every selection (leaving the ~17pt mark) does not
  reliably restore the icon, and `boringNotch` was running throughout both the working and failing
  cases.

The interval matches `SystemStatsService.runLoop`, whose default tick is 10 s plus sampling time.

Root cause: `menuBarSegments` and `menuBarIcon` are computed **on the `FluxaApp` struct**, and they
read observable state — `viewModel.systemStats`, `viewModel.agentUsage`, `settings`. Observation
registered while evaluating an `App`'s `body` invalidates the whole scene graph, so each sample
re-evaluates the `Scene` and re-applies the `MenuBarExtra`'s insertion. Under that churn macOS parks
the item and persists `visible = 0`.

## Fix

The contract is in `specs/18-menubar-item-cannot-return.md`; the summary below is the shape of it.

Scope the observation to a `View` so a new sample re-renders the label instead of the scene. The
strip's dependency reads must move out of the `App` struct into the label view's own `body` — the
`FluxaLaunchLabel` wrapper is already the right shape; it is the *arguments* computed at App level
that leak the dependency upward. `MenuBarExtra`'s content and label should close over the services,
not over values read eagerly in `FluxaApp.body`.

Keep `isInserted: .constant(true)`. It is not the cause and not the cure, but declining a gesture
that removes the app's only surface is still the right call, and it is harmless — the controls
confirm it costs nothing.

Verification is objective and does not need the owner: after the change, `AXExtrasMenuBar` must
report a Fluxa child at `y≈4.5`, and `NSStatusItemChangeVisibilityAction` must not repeat on the
sampling interval. `.plan` has no view test target, so this is a measurement, not a unit test.

## Notes

- Do not ship 2.9.2 (19) with the current release notes: they announce this bug as fixed.
- Any user who has ever Cmd-dragged the icon out is also in the flag state, and has no way to tell
  the app is even running.

## Second correction — the scene churn was real, and it was not the cause either

Build 19 shipped the scene-scoping fix. The churn stopped: `NSStatusItemChangeVisibilityAction` no
longer repeats on the sampling interval, and the control apps still behave as described. The icon
was **still missing**, so the root cause in the Correction section above is disproved in turn. It
was a genuine defect and the fix is worth keeping; it was not this bug.

Two separate defects were found, and both had to be fixed before the icon returned.

### Defect A — the launch path deadlocked the main thread

`PopoverViewModel.init` → `refreshStates()` → `PeripheralBatteryService.refresh()` →
`PeripheralBatterySampler.sample()` → `IOBluetoothDevice.pairedDevices()`.

Without an existing Bluetooth grant, the first `pairedDevices()` call spins up IOBluetooth's
CoreBluetooth coordinator, whose initialiser blocks on a semaphore that is never signalled. On the
launch path that deadlocks the main thread, so the status item is never created at all.

`BluetoothAudioService.refresh()` already guards against exactly this, with the reason written down;
the sampler had no such guard. Fixed by copying the precedent — `CBManager.authorization ==
.allowedAlways` before enumerating — in `Sources/FluxaCore/Services/PeripheralBatterySampler.swift`.

The guard as first written failed the sampler's own latency benchmark, and the benchmark was right.
`CBManager.authorization` is an XPC round trip to `bluetoothd`: measured at **8.6 ms** per call,
against **0.026 ms** for the whole IOKit power-source traversal it protects. The gate cost three
hundred times the work. The answer is now held in `BluetoothAuthorizationCache` for three seconds —
shorter than the sampling interval, so a permission granted or revoked still takes effect on the
next reading, and repeated sampling pays for one lookup instead of one per call.

Worth recording as a general point: a correctness fix that reaches for a system authorization API on
a hot path should assume the call is expensive until measured. The bound in
`Tests/FluxaCoreTests/PeripheralBatterySamplerTests.swift` caught this immediately and was left
unchanged.

### Defect B — Control Center was applying another app's denial to Fluxa

This is the one that made the bug look unfixable, and it is not in Fluxa's code at all.

Control Center keeps an allow-list of menu bar items in
`~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist`,
as a binary plist embedded under `trackedApplications`. Each entry carries a `location.bundle._0`
(the owning app), an `isAllowed` boolean, and a `menuItemLocations` array naming the items that
entry governs.

On the owner's machine, **eight** entries listed `com.giuseppe.fluxa` in their `menuItemLocations`.
Two of them — `com.google.antigravity` and `com.openai.codex` — were `isAllowed = False`. Control
Center resolved Fluxa's status item through that mapping and applied the other app's denial. Fluxa's
own entry said `isAllowed = True` and lost.

That explains every failed recovery on record: the mapping is not in Fluxa's bundle, not in Fluxa's
preferences domain, and not reachable from the System Settings toggle, which only edits an app's own
entry. Reinstalling, replacing the bundle, resetting Control Center and toggling the switch all left
it untouched.

Decisive control: a fifteen-line `MenuBarExtra` binary renamed to `com.giuseppe.fluxa` was blocked
identically; the same binary as `com.test.fluxa15` was visible. So the bundle identifier, not the
code, was what the system refused.

Corroborating detail: Antigravity's own icon was parked off-screen at `x=-1, y=981`, consistent with
its `isAllowed = False`. The two culprits are the two agents that launch Fluxa as a child process,
which is the plausible route by which macOS 26's menu bar migration conflated them.

Public reports of the same mechanism, found after the fact and matching the measurements:
[CodexBar #1440](https://github.com/steipete/CodexBar/issues/1440),
[Fix Tahoe menubar missing 3rd party apps](https://tongfamily.com/2025/10/29/mac-fix-tahoe-menubar-missing-3rd-party-apps/),
[AeroSpace #1968](https://github.com/nikitabobko/AeroSpace/discussions/1968).

### What was done about B

All eight foreign claims were removed and Fluxa's own entry set to `isAllowed = True`, after backing
up the plist. The six claims that were `isAllowed = True` — iTerm2, Terminal, and four leftovers from
this investigation's own test bundles — did no harm that day, but any one of them would have taken
Fluxa down the moment the owner hid that app from the menu bar. Removing only the two culprits would
have left the bug loaded.

This is a user-machine repair, not a code change. Fluxa cannot write that file: it is in another
app's group container and TCC-protected. There is no in-app fix for B and the ticket should not
pretend otherwise.

## Answer

Both defects fixed; the icon is back. Verified on the owner's machine on 2026-09-13 with
2.9.2 (20) running from `/Applications`: `AXExtrasMenuBar` reports a Fluxa child at `y=4`, and
re-reading the Control Center plist shows one entry for Fluxa, owned by Fluxa, with no foreign
claims among the 96 tracked applications.

What to carry forward:

- **Recurrence is a real risk and is not under Fluxa's control.** Any app that picks up a claim on
  `com.giuseppe.fluxa` and is then hidden from the menu bar reproduces this. Worth a documented
  recovery procedure for users, since no amount of reinstalling helps and the symptom is
  indistinguishable from the app being broken.
- **Do not ship distinct bundle identifiers for test builds carelessly.** Four of the eight stale
  claims came from throwaway bundles created during this investigation, each of which left a
  permanent entry.

## Comments

- 2026-09-05, codex: found and fixed while investigating the owner's missing icon. Established that
  the registration and preferences live under `~/Library`, not in the bundle, so no amount of
  reinstalling or resetting Control Center could clear them; the fixed local bundle stays running.
  Called for a build past 18, installed by the owner — `/Applications` is owner-only.
- 2026-09-05, claude: reopened. The owner reported the icon still missing on build 19, which carries
  the fix, so the ticket was reinvestigated from scratch. Two of my own earlier conclusions were
  wrong and are retracted in the Correction section: that the persisted flag was the cause, and that
  the item was never created at all. The second came from a window-list probe that cannot see menu
  bar items; the Accessibility API can, and it does see one. Status returned to `codex-active`.
- 2026-09-05, claude: root cause confirmed directly rather than inferred —
  `"NSStatusItem VisibleCC Item-0" = 0` is present in the owner's domain. Ticket written after the
  fact because the change reached the tree without one, riding along with ticket 16's diff; a fix
  that changes whether the app has any UI at all should not ship as an unexplained line in someone
  else's ticket. Build, tests and signature verified together with 16.
- 2026-09-05, codex: moved live strip observation from `FluxaApp` into
  `Sources/Fluxa/Views/MenuBarStripLabel.swift`; added
  `Sources/Fluxa/Views/FluxaVisualStyleRoot.swift` so all seven scene roots defer
  `settings.visualStyle` observation into view evaluation; updated
  `Sources/Fluxa/App/FluxaApp.swift` while preserving `isInserted: .constant(true)` and
  `FluxaLaunchLabel` launch behavior. `swift build -c release -Xswiftc -warnings-as-errors`
  passed; `swift test` passed 115 tests. Ready for Accessibility/status-item churn validation
  and local bundle launch.
- 2026-09-13, claude: reinvestigated after build 19 shipped the scene-scoping fix and the icon was
  still missing; the root cause recorded above is retracted in the Second correction. Kept the
  scene-scoping change — it fixed a real defect and the churn measurements were sound — and found two
  further defects, one in Fluxa (`PeripheralBatterySampler`, main-thread deadlock at launch) and one
  in the owner's Control Center allow-list. Fixed both. Verified the icon present from
  `/Applications` at 2.9.2 (20), with `swift build -c release` clean and 115 tests passing. The
  `PeripheralBatterySampler` edit is production Swift and so is Codex's by the role contract; the
  owner asked for it to be made directly and it should be read as theirs, not as a precedent.
