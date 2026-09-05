# Effort Map — Swift App Expansion

**Goal**: grow Fluxa with features it lacks, designed and written from scratch under a
Swift 6 concurrency design.

**This is not a port.** The original brief asked to port from
`vorssaintapp/vorssaint-utils`; ticket `01` established that its GPL-3.0 licence is
incompatible with Fluxa's Apache-2.0, and that the components the brief named don't exist
there anyway. The effort was re-scoped to **clean-room**: feature ideas are fair game
(ideas are not copyrightable), that repository's source code is not.

**Started**: 2026-08-30
**Tracker conventions**: `docs/agents/issue-tracker.md`
**Status vocabulary**: `docs/agents/triage-labels.md`
**Who does what**: `docs/agents/roles.md`

## Notes

- Fluxa is a single SPM executable target (`Sources/Fluxa`), `swift-tools-version: 5.9`,
  macOS 14+. Ported code lands inside this target unless a ticket argues for a split.
- The package builds in **Swift 5 language mode today**. Swift 6 strict concurrency is a
  goal of this effort, not a starting condition. Enabling it is its own ticket and should
  land after the ported components exist, not before.
- `HANDOFF.md` carries standing release rules (Sparkle updater, build numbering, DMG+ZIP
  pairing). Nothing in this effort may violate them; a conflict is a `needs-info` blocker.
- **Clean-room rule, binding on every agent**: do not read, fetch, clone or quote source
  from `vorssaintapp/vorssaint-utils` — or from any GPL codebase — while working this
  effort. Only the public file tree was ever read, never file contents. Every design
  decision must be derivable from Fluxa's own code, Apple's documentation, and the
  feature description in the ticket. If a ticket can't be implemented without looking
  at someone else's source, set `needs-info` and say so.
- Group A (03–08) extends the metrics stack Fluxa already owns. Group B (09–13) is small
  self-contained quick actions. Group C (clipboard history, snippets, window management,
  mouse tweaks) is deferred — each is a mini-project needing Accessibility or Input
  Monitoring, not a ticket.
- Rejected outright: fan control (privileged root helper + SMC writes), alt-tab switcher
  and Dock preview (private APIs), app uninstaller (destructive file deletion).
- **There is no test target.** `Package.swift` has one `executableTarget`; `Tests/FluxaScreenshots/`
  is an empty directory. `swift test` does nothing. Ticket `02` fixes this and blocks
  every `antigravity-validation` transition.

## Decisions so far

_(append one line per resolved ticket: number, gist, link to the ticket file)_

- **01** — Survey done, effort **re-scoped from port to clean-room**. Upstream is **GPL-3.0**, Fluxa is
  **Apache-2.0**: one-way incompatible, so porting is not legally available without
  relicensing Fluxa. Separately, the pipeline/telemetry/crypto components named in the
  brief **do not exist upstream** — the repo is a 415-file competing menu-bar app whose
  only overlap with Fluxa (metric samplers, update service) Fluxa already implements.
  Owner chose clean-room: take feature ideas, write everything from scratch, Fluxa stays
  Apache-2.0. → `issues/01-survey-vorssaint-utils.md`

- **06** — Spec written. Charge/time-remaining are `SystemMetricID` cases; power source
  (AC/battery) is not — exposed as `isOnACPower: Bool?` instead, since it doesn't reduce to
  a `Double`. Time-remaining publishes a negative sentinel ("Calculating…") until three
  consecutive IOKit estimates agree within 20%, so the UI never shows a jumpy figure.
  → `issues/06-battery-and-power.md`, `specs/06-battery-and-power.md`

- **08** — Spec written. New `AlertThreshold` (Codable, JSON in `AppSettings`) plus a
  separate `AlertEvaluator` fed off a new `SystemStatsService.onSample` hook — evaluation
  stays out of the sampler itself. 30s dwell + 10% reset-band hysteresis. First feature to
  use `UNUserNotificationCenter`; permission follows `PermissionsService`'s existing
  lazy-ask pattern. → `issues/08-threshold-alerts.md`, `specs/08-threshold-alerts.md`

- **07** — Spec written. Not built on `BluetoothAudioService`/`IOBluetoothDevice` — no
  public battery property there, and AirPods' battery has no public API at all, so AirPods
  and Bluetooth audio devices are explicitly out of scope. Magic Mouse/Keyboard/Trackpad
  battery instead reuses `06`'s `IOPSCopyPowerSourcesList` call, generalized to every
  non-internal source (filtered by transport type, not list position — a correction to an
  assumption `06` made, applied without touching `06`'s shipped code). Presence hysteresis
  (2 missed refreshes) instead of `06`'s value hysteresis, since here what's unstable is
  whether a device is in the list at all. → `issues/07-peripheral-battery.md`,
  `specs/07-peripheral-battery.md`

- **09** — Spec written. `NSColorSampler` gives the whole picker interaction for free (no
  Screen Recording permission, no hand-rolled loupe) — confirmed as the only sane approach
  per the ticket's own note. Hex `#RRGGBB` only, no format setting: there's no existing
  per-action settings surface to hang one on for a single-tap action with no window.
  Sampled color always converts to sRGB before formatting so the hex matches what every
  other tool (browser inspector, design tools) would show for the same pixel; a failed
  conversion or an Esc cancellation both decline silently. Amended (D6) after owner testing
  the shipped build: a silent clipboard copy wasn't enough feedback, so a successful pick
  now shows a small transient click-through HUD (swatch + hex) instead of a system
  notification, which would need a permission prompt for a one-shot action.
  → `issues/09-color-picker.md`, `specs/09-color-picker.md`

- **11** — Spec written. `NSWorkspace.runningApplications` (`.regular` policy) is the list,
  same as the ticket proposed, plus Fluxa excluding itself from its own kill list.
  `CPUUsageSampler` (06) turned out to be machine-wide only, not reusable per-process, so
  sort order instead uses a single `proc_pid_rusage` sample (cumulative CPU time) taken
  fresh per popover open — a deliberate simplification since nothing displays the number,
  only orders by it. `terminate()` then `forceTerminate()` after a 2s timeout, no raw
  signals. First `.confirmationDialog` anywhere in the app. → `issues/11-kill-process.md`,
  `specs/11-kill-process.md`
- **15** — Spec written. Antigravity joins the usage strip as a third provider, from the
  Keychain item (service `gemini`, account `antigravity`) and one JSON endpoint,
  `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`. Four pool meters; the
  API reports fraction *remaining*, so it is inverted into `percentUsed`. **Not a clean-room
  ticket**: scoping established Google's interface facts from an existing permissively-licensed
  integration. Facts about a third party's interface carry no notice obligation, so Fluxa ships
  no attribution — but the expression must stay Fluxa's own, so the reader follows
  `ClaudeUsageReader`'s shape and nothing is transcribed (see the ticket's Provenance section).
  It also **narrows the read-only credential rule**:
  Antigravity's token must be refreshed via Google OAuth, which is safe here only because
  Google's refresh grant does not rotate the refresh token — so refreshing never invalidates
  Antigravity's own login, provided Fluxa never writes back to its Keychain item. Derived
  tokens are cached in Fluxa's own file, fingerprint-bound to the refresh credential so an
  account switch cannot replay the previous account's token. Local token history (spend,
  usage trend) excluded — needs SQLite + protobuf that `AgentLogScanner` has no shape for.
  → `issues/15-antigravity-usage.md`, `specs/15-antigravity-usage.md`

## Fog

Open questions, in rough priority order. Each becomes a ticket when it's sharp enough.

- ~~What is actually in `vorssaint-utils`?~~ **Resolved by ticket 01.**
- ~~Which option?~~ **Resolved: clean-room, groups A + B. Tickets 03–13 written.**
- Ticket `03` is the real dependency risk: it changes `SystemMetricID`/`SystemStatsSample`
  and four other tickets sit behind it. If its design is wrong, 04–08 all rework.
- How should the package be restructured so it is testable at all — test the executable
  directly, or extract a library target? **→ ticket 02**
- ~~14 — per-app volume mixer feasibility?~~ **Resolved, `wontfix`.** Checked the actual
  CoreAudio SDK headers: the `Process` class has no volume property, `ProcessMute` only
  mutes the current process, and the macOS 14.2 process-tap API is capture-only, no write
  path. No public per-process volume control exists on macOS at all — a mixer is only
  possible via a virtual audio driver, which is out of scope for this app (same grounds as
  the fan-control rejection). See `issues/14-per-app-volume-mixer.md`.
- What is Fluxa's current concurrency posture — how many `@MainActor` types, how much
  shared mutable state — and how far is it from compiling under strict concurrency?
- ~~Upstream crypto security properties?~~ **Moot — there is no crypto component upstream.**
- ~~Where does telemetry data go?~~ **Moot — there is no telemetry upstream.**
