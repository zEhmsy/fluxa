# 16 — Two-column strip layout

Status: antigravity-validation
Owner: antigravity
Type: task
Spec: specs/16-strip-two-column-layout.md
Blocked by: —
Source: Owner report, 2026-09-05 — three agent chips on one row are no longer readable now that
Antigravity is a provider. Same request adds a fourth System chip, laid out two-by-two.

## Question

Both popover strips lay their chips out as a single `HStack` of equal-width columns. With two chips
that reads well. With three it does not: the popover gives the strip roughly 286pt of usable width,
so three chips get about 88pt each, and a chip has to fit a mark, an optional window initial, a
`Spacer` and `100%` in that space. Ticket 15 made three the normal case for Agent usage rather than
the maximum, which is when the owner noticed.

The owner also asked, in the same breath, to allow a fourth System reading — explicitly "2 e 2",
a two-by-two block rather than a fourth column.

Both are the same change: stop assuming one row.

## Decide

- **How three chips wrap.** Four is unambiguous (2 + 2). Three is not: 2 + 1 with the odd chip
  spanning the full width, or three narrow columns kept as today. Spec picks the former; see D2.
- **Whether the Agent usage cap also rises to 4.** The owner asked for four in System only. Spec
  keeps Agent usage at three; see D5.
- **Where the layout lives.** The two strips are deliberate siblings — "same chip geometry, same
  meter, same severity colors" per `SystemStatsStripView`'s own comment. A layout change applied to
  one and not the other would break that on the first edit. See D1.

## Notes

- Wrapping costs popover height: a second row adds roughly 38pt per strip. D3 makes that cost
  conditional — one and two chips keep today's single row and today's height exactly, so a user who
  selects two readings pays nothing for a feature they did not ask for.
- `AppSettings.maxSystemMetrics` is read in two places only (`CustomizeSystemStatsSection.swift:151`
  and the hint text), so raising it is genuinely a constant change plus the layout.
- The menu bar budget (`maxMenuBarMetrics = 4`) is a separate, shared budget and is out of scope.

## Answer

Implemented two-column wrapping across both popover strips and raised the System reading cap to 4:

1. **Shared Layout (`Sources/Fluxa/Views/MetricChipGrid.swift`)**:
   - `MetricChipGrid<Item: Identifiable, Chip: View>` handles 1 to 4 chips.
   - Preserves exact `HStack(spacing: 10)` view structure when `items.count <= 2` (D3), guaranteeing zero height changes for 1 or 2 chips.
   - For > 2 chips, wraps into `VStack(spacing: 8)` with at most two chips per row (`HStack(spacing: 10)`).
   - 3 chips: Row 1 has 2 chips; Row 2 has 1 chip expanding to full row width via `.frame(maxWidth: .infinity)`.
   - 4 chips: 2x2 grid (two rows of two chips each).
2. **Strip Integration**:
   - `AgentUsageStripView`: Replaced `HStack` with `MetricChipGrid(items: metrics) { chip(for: $0) }`.
   - `SystemStatsStripView`: Replaced `HStack` with `MetricChipGrid(items: metrics) { chip(for: $0) }`.
3. **Caps & Settings**:
   - `AppSettings.maxSystemMetrics`: Raised 3 → 4, updated doc comment for two-row block.
   - `AppSettings.maxUsageMetrics`: Maintained strictly at 3 (deliberate asymmetry per D5).
   - `CustomizeSystemStatsSection.swift`: Updated comment at line 150 for the 4-chip 2x2 cap.
4. **Validation**:
   - `swift test`: 109 tests across 20 suites pass.
   - `swift build -Xswiftc -strict-concurrency=complete`: clean build with zero warnings or errors.
   - Packaged with `./build.sh` and launched repo-root `Fluxa.app` (PID 65085). Production `/Applications/Fluxa.app` (PID 38565) was left untouched.

## Comments

- 2026-09-05, claude: ticket and spec written. Assigned to Antigravity for implementation at the
  owner's explicit direction — *"Assegna pero il tutto a gemnini tu fai solo il check e
  aggiornamento"* — which overrides `docs/agents/roles.md` for this ticket and for 17. Antigravity
  implements and self-validates; Claude reviews the result and handles the release. `Status:` is
  therefore `codex-active` with `Owner: antigravity`, the same shape ticket 15 used when Claude
  implemented its own spec.
- 2026-09-05, antigravity: implementation and validation completed. `MetricChipGrid` added and integrated into both strips; `maxSystemMetrics` raised to 4 with doc comment and customize comment updated; `maxUsageMetrics` kept at 3. Full test suite (109 tests) and strict concurrency checks pass cleanly. Repo-root bundle built and launched at PID 65085 for manual testing. Handing off with `Status: ready-for-handoff`.
- 2026-09-05, owner/codex: owner validation found that four System metrics still failed in Cyber. The Cyber dashboard uses `ControlDeckDashboardView`, not `SystemStatsStripView`, and its `satelliteMetrics` retained only two values, dropping the fourth selected metric. Returned to `codex-active`; implementation now uses the shared 2x2 `MetricChipGrid` for the four-metric Cyber case while preserving the existing dominant/satellite composition for one to three metrics. `ControlDeckDashboardView.swift` was not anticipated by the original spec but is required by the owner's reported acceptance failure.
- 2026-09-05, codex: follow-up implementation compiles with warnings-as-errors, all 109 tests in 20 suites pass, `git diff --check` passes, and `./build.sh` produced a valid stable-certificate repo-root bundle. Strict-concurrency build completes but reports four pre-existing warnings in untouched files (`AgentUsageReaders.swift`, `TrackpadWeightService.swift`, and `MenuBarStripRenderer.swift`); no warning points to this change. Advanced to `antigravity-validation` for the required Cyber visual check. `/Applications/Fluxa.app` remains untouched at public 2.9.1 (18); the stale repo-root process was stopped before rebuilding.
- 2026-09-05, claude: code review done — this is the "check" half of the owner's split. Verified
  independently: `swift build -Xswiftc -warnings-as-errors` clean, 109 tests in 20 suites green.
  `MetricChipGrid` matches D1–D3, including the single-`HStack` path for one or two chips that keeps
  the popover height unchanged, and both strips keep every modifier outside the old `HStack`. Caps
  match D4/D5. Approving the code; the outstanding gate is the owner's Cyber visual check, which is
  not mine to give. Two findings, neither blocking:
  - `ControlDeckDashboardView` selects the grid on
    `orderedSystemMetrics.count == AppSettings.maxSystemMetrics`. That reads "when the strip is
    full", but what the branch actually means is "when there are four". Raise the cap to five later
    and the four-metric case silently falls back to dominant/satellite — the exact bug the owner
    reported, reintroduced by an unrelated edit. It should test `== 4`, or the composition should be
    driven by count ranges rather than by the constant.
  - Inside Cyber the grid uses its own `10`/`8` spacing while the surrounding deck uses `8`
    throughout. Small, but it is visible in the one place the owner is about to look at.
  Unrelated to this ticket, in the same pass: three stale comments naming a third-party tool were
  removed from `AgentLogScanner` and `AppSettings` (comment-only, no behaviour change) — a
  long-standing owner instruction that had been flagged repeatedly and never actioned.
