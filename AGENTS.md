# AGENTS.md

This repo's agent configuration lives in `CLAUDE.md` and `docs/agents/`. This file is a
pointer so that Codex, Antigravity and any other agent read the same source as Claude
rather than a second copy that drifts out of sync.

**Read these before doing anything:**

| File                            | What it tells you                                                    |
| ------------------------------- | -------------------------------------------------------------------- |
| `docs/agents/roles.md`          | Which phase you own, what you may and may not touch, how you hand off |
| `docs/agents/issue-tracker.md`  | Where tickets and specs live, and their format                        |
| `docs/agents/triage-labels.md`  | The `Status:` vocabulary and what each state means                    |
| `docs/agents/domain.md`         | Which docs to read before exploring the codebase                      |
| `CLAUDE.md`                     | Repo rules, build/test commands, the role-division summary            |
| `HANDOFF.md`                    | Standing release rules — these override a plausible-looking change    |

## The short version

Fluxa is a macOS menu-bar app: a single SPM executable target at `Sources/Fluxa`,
`swift-tools-version: 5.9`, macOS 14+, **Apache-2.0**. The current effort adds features it
lacks, tracked in `.plan/swift-app-expansion/`.

**Clean-room rule — binding.** This effort takes feature *ideas* from other menu-bar apps,
never their code. Do not read, fetch, clone or quote source from
`vorssaintapp/vorssaint-utils` (GPL-3.0, incompatible with Fluxa's Apache-2.0) or any
other GPL codebase. Derive everything from Fluxa's own code, Apple's documentation, and
the ticket text. Rewriting someone's Swift in your own words is still a derivative work.
If a ticket looks like it needs their implementation, set `Status: needs-info` and stop.

Three agents, one phase each:

- **Claude** owns `spec-pending` — architecture, API contracts, Swift 6 concurrency
  design, spec authoring.
- **Codex** owns `codex-active` — native Swift implementation, algorithm translation,
  memory management.
- **Antigravity** owns `antigravity-validation` — tests, fuzzing, benchmarks, strict
  concurrency checks, then builds and launches the repo-root `Fluxa.app` so the owner can
  try it by hand. **Never touches `/Applications/Fluxa.app`** — that's the production
  install; see `docs/agents/roles.md`.

Work only tickets whose `Status:` is the state you own. When you finish, advance the
`Status:` and `Owner:` lines and append to `## Comments`. When you're blocked on a
decision the owner must make, set `Status: needs-info` and stop — don't guess.

**Release boundary**: committing, pushing, bumping the build number, packaging, and
updating the Sparkle feed are never part of resolving a ticket. `ready-for-handoff` means
"built and running locally for the owner to try," not "shipped." The owner does the
actual release themselves, by hand, following `HANDOFF.md`, once they're satisfied.

## Build and test

```bash
swift build
```

**There is no test target yet.** `Package.swift` declares a single `executableTarget`,
and `Tests/FluxaScreenshots/` is an empty directory — `swift test` currently does
nothing. Standing up a `testTarget` is ticket `02` and blocks every
`antigravity-validation` state. Do not report a validation pass until it exists.

Once it does:

```bash
swift test
swift build -Xswiftc -strict-concurrency=complete   # strict-concurrency check
```
