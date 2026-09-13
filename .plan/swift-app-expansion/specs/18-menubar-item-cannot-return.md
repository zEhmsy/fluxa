# Spec 18 — Keep the menu bar item still

Ticket: `issues/18-menubar-item-cannot-return.md`
Author: claude, 2026-09-05

Stop the `MenuBarExtra` scene from being re-evaluated on every system sample, so macOS stops parking
the status item and writing `visible = 0`.

> **Superseded as a bug fix, 2026-09-13.** This spec was implemented in build 19 and did what it says
> — the churn stopped — but the icon was still missing, so it was not the cause. Keep the change: the
> churn was a real defect. The two defects that actually caused the reported symptom are recorded in
> the ticket's *Second correction*, and neither is addressed here.

## The mechanism, stated once

`AppSettings` and `PopoverViewModel` are both `@Observable`. SwiftUI records a dependency wherever a
property of an observable object is *read*, and it invalidates whatever was being evaluated at that
moment. `FluxaApp.body` returns a `Scene`, so a dependency recorded there invalidates the whole
scene graph — every `Window` as well as the `MenuBarExtra`.

`menuBarIcon` and `menuBarSegments` are computed properties on `FluxaApp`. They are not views; they
are called *during* `FluxaApp.body`, and they read `viewModel.systemStats`, `viewModel.agentUsage`
and `settings.systemMenuBarMetricIDs` / `settings.usageMenuBarMetricIDs`. `SystemStatsService`
publishes a new sample about every ten seconds, so the scene is rebuilt about every ten seconds and
the `MenuBarExtra`'s insertion is re-applied each time. That is the churn measured in the ticket:
twenty `NSStatusItemChangeVisibilityAction` events in three minutes, against zero for a control app.

The rule that follows, and the whole of this spec: **`FluxaApp.body` must not read a property of any
observable object.** It may pass the objects themselves along.

## D1 — Move the strip into its own view

Add a `View` that owns the strip's reads. `Sources/Fluxa/Views/MenuBarStripLabel.swift` is the
natural home — it belongs beside `MenuBarStripRenderer`, not in `App/`.

```swift
struct MenuBarStripLabel: View {
    let settings: AppSettings
    let viewModel: PopoverViewModel
}
```

`menuBarIcon` and `menuBarSegments` move onto it verbatim — same renderer call, same
`AppSettings.maxMenuBarMetrics` limit, same `bolt.circle.fill` fallback when
`MenuBarStripRenderer.image(segments:)` returns nil. This is a relocation, not a redesign: the
rendered strip must be identical pixel for pixel.

Holding `settings` and `viewModel` as plain `let` properties is correct and sufficient. Observation
is established by the reads inside `body`, not by a property wrapper, so `@State` / `@Bindable` are
not needed and `@Environment` would only move the same reads somewhere else.

`FluxaApp` then reduces to passing the two objects through, and its `menuBarIcon` and
`menuBarSegments` are deleted rather than left unused.

## D2 — `FluxaLaunchLabel` keeps its job

`FluxaLaunchLabel` exists for its `.task`: offering the permissions window once, at launch, even if
the user never opens the popover. That behaviour must survive unchanged — same guard on
`settings.hasPresentedPermissionsSetup`, same `openWindow`, same `bringToFront`.

Note it currently reads `settings.hasPresentedPermissionsSetup` inside a `.task`, not inside `body`,
so it is not part of the bug. Leave it alone beyond whatever the composition in D1 requires. Whether
`MenuBarStripLabel` wraps `FluxaLaunchLabel` or sits inside it is Codex's call; the only requirement
is that neither the strip's reads nor the launch task end up back in `FluxaApp.body`.

## D3 — The same leak in the environment modifiers

Every scene in `FluxaApp.body`, the six `Window`s included, carries:

```swift
.environment(\.fluxaVisualStyle, settings.visualStyle)
```

That is another read of an observable property in `FluxaApp.body`, by the same mechanism. It fires
far less often than the sampler — only when the user changes appearance — but when it does, it
rebuilds every scene and re-inserts the status item, which is exactly the event we are trying to
eliminate. A user toggling the visual style is a plausible way to lose the icon.

Push it inward: each scene's root view already receives `.environment(settings)`, so the style can be
applied inside that view's own `body` instead of at the scene level. The seven call sites are
mechanical and must all be done — leaving one behind leaves the bug reachable.

If a scene's root view cannot reasonably read it itself, a one-line wrapper view that applies the
modifier is acceptable. What is not acceptable is reading `settings.visualStyle` in `FluxaApp.body`.

## D4 — `isInserted:` stays

Keep `MenuBarExtra(isInserted: .constant(true))`.

It is not the cause and not the cure — a control app carrying the same parameter shows its item
immediately and logs none of the churn. It is kept on its own merits: Cmd-dragging away the icon of
an app whose icon is its only surface is a way to lose the app, not a preference. Removing it in the
same change would confound the verification below.

## Verification

Objective, and does not need the owner. Measure on a built `.app` launched with `open`, never by
running the executable from a shell — a process started outside the GUI session gets no status item
at all, which is a trap that already cost this ticket one wrong diagnosis.

1. **The item is on the menu bar.** Query the Accessibility API for the Fluxa process:
   `AXExtrasMenuBar` must exist and report one child at `y ≈ 4.5`. A child at `y ≈ 981` means macOS
   parked it off-screen and the fix has not worked.
2. **The churn is gone.** With at least one System metric selected, so the sampler is running:

   ```
   log show --last 3m --predicate 'process == "Fluxa"' --info --debug \
     | grep -c NSStatusItemChangeVisibilityAction
   ```

   Expect a small constant from the launch itself and **no recurrence on the ten-second sampling
   interval**. Twenty events in three minutes is the failing baseline.
3. **The strip still updates.** Over the same window the readings must visibly change — a fix that
   freezes the label would also pass steps 1 and 2 and would be worse than the bug.
4. **The flag is not rewritten.** Delete `NSStatusItem VisibleCC Item-0` from
   `com.giuseppe.fluxa`, launch, wait a minute: the app must not recreate it as `0`.
5. `swift build -c release -Xswiftc -warnings-as-errors` clean, existing suite green, `./build.sh`
   clean.

There is no view test target and this does not justify inventing one. If any pure logic falls out of
the move, put it in `FluxaCore` and test it there; do not force it.

## Out of scope

Clearing a stale `NSStatusItem Visible…` flag on the user's behalf. It was rejected when this ticket
was first written and the reasoning holds: writing macOS's own status item bookkeeping to undo a
gesture fights the system on every launch. Once the app stops causing the flag, the flag stops
mattering.
