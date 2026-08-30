# Agent Roles — Swift App Expansion

Three agents work this effort. Each owns a distinct phase; a ticket's `Status:` says who
holds it right now (see `docs/agents/triage-labels.md`). No agent starts work on a ticket
whose `Status` is not its own.

## Claude — architecture and orchestration

**Owns**: `spec-pending`

- System architecture: module boundaries, ownership graph, where ported behaviour lands
  inside `Sources/Fluxa/`.
- API contract design: the public surface of each ported component, expressed as Swift
  protocols before any implementation exists.
- Swift 6 concurrency design: which types are `actor`s, which are `Sendable`, which are
  `@MainActor`-isolated, and where isolation boundaries sit. **Note the current state**:
  `Package.swift` declares `swift-tools-version: 5.9`, so the package builds in Swift 5
  language mode today. Strict concurrency is a migration target for this effort, not an
  existing property — design for it, and treat enabling it as its own ticket.
- Prompt orchestration: writing the spec files that Codex and Antigravity execute
  against, and deciding ticket order and blocking.
- Feature design from a description: turning a one-line feature idea into a contract
  Fluxa can implement on its own terms. **Not** reverse-engineering — see the clean-room
  rule in `docs/agents/issue-tracker.md`.

**Produces**: `.plan/swift-app-expansion/specs/NN-<slug>.md` via `/to-spec`.
**Does not**: write production Swift, write tests, or run benchmarks.

**Hands off** by writing the spec, setting `Status: codex-active` and `Owner: codex`.

## Codex — native Swift implementation

**Owns**: `codex-active`

- Implements the spec in native Swift against the contracts Claude defined. The
  protocols and isolation annotations in the spec are the brief, not a suggestion — a
  disagreement goes back as a `## Comments` entry and `Status: needs-info`, not a
  unilateral redesign.
- Writes original Swift against Apple's frameworks. **No third-party source is consulted**
  — the clean-room rule in `docs/agents/issue-tracker.md` is binding, and a
  Swift-to-Swift retranscription of GPL code would still be a derivative work.
- Memory management: no retain cycles. Closures that capture `self` and escape use
  `[weak self]`; delegate and parent references are `weak` or `unowned` as the ownership
  graph in the spec dictates. Every `Task { }` that outlives its creator is accounted for.
- Refactoring adjacent code only as far as the spec's scope requires.

**Produces**: Swift sources under `Sources/Fluxa/`, and a build that passes
`swift build`.
**Does not**: author the API contract, change the isolation model, or declare the work
validated.

**Hands off** by setting `Status: antigravity-validation` and `Owner: antigravity`, with
a `## Comments` entry listing the files touched and anything the spec didn't anticipate.

## Antigravity — validation

**Owns**: `antigravity-validation`

- Unit tests using Swift Testing where the target supports it, XCTest otherwise.
  `FluxaCoreTests` exists as of ticket `02`; add new test files under `Tests/` as the
  ticket requires.
- Edge-case fuzzing: boundary values, malformed input, empty and maximal collections.
  For the sampler tickets specifically: counter wraparound, hardware that reports nothing
  (a desktop Mac has no battery), and devices that disappear mid-sample.
- Performance benchmarks for anything on a sampling or menu-bar refresh path, with a
  recorded baseline so regressions are visible.
- Strict concurrency validation: build with
  `-Xswiftc -strict-concurrency=complete` and report every warning. A ticket does not
  reach `ready-for-handoff` while it introduces new concurrency warnings.
- Verifies the retain-cycle claim rather than trusting it.
- **Builds and launches a local copy for the owner to test by hand.** After every check
  above passes: quit any Fluxa process already running from this repo checkout (match by
  executable path, e.g. `pgrep -fl "Fluxa.app/Contents/MacOS/Fluxa"` and exclude anything
  under `/Applications`), run `./build.sh`, then `open Fluxa.app` from the repo root. This
  is the **only** copy that gets touched.
  - **Never touch `/Applications/Fluxa.app`.** That is the production install, managed by
    Sparkle, versioned per the rules in `HANDOFF.md`. `build.sh` ad-hoc signs by default
    (see the comment above its signing step) — the repo-root bundle is explicitly not a
    distributable artifact, and must never overwrite or be copied into `/Applications`.
  - Both copies share one `UserDefaults` domain (`com.giuseppe.fluxa`) because they share
    a bundle ID — that's expected and is how the owner's existing settings carry over
    into the test build. It is not a reason to touch the production copy instead.
  - Note the running pid in `## Comments` so the next agent (or the owner) can find and
    quit it without guessing.

**Produces**: tests under `Tests/`, benchmark numbers, a validation verdict in the
ticket's `## Answer` section, and a running local build at the repo-root `Fluxa.app` for
manual testing.
**Does not**: fix the implementation — a failure sends the ticket back to `codex-active`
with a reproducible case. Does not commit, push, or touch anything under
`/Applications` — see the escalation rule below.

**Hands off** by setting `Status: ready-for-handoff` and leaving the local build running
— or back to `codex-active` on failure. `ready-for-handoff` means "built, tested, and
running locally for the owner to try," not "shipped." Nothing publishes further until the
owner says so.

## Escalation

Any agent may set `Status: needs-info` and stop. Do so rather than guessing when a
decision changes the shape of the result, when the spec conflicts with `HANDOFF.md`, or
when upstream behaviour can't be determined from the source.

## Release boundary — binding on every agent

Committing, pushing, bumping the build number, packaging a release, or updating the
Sparkle feed are **never** part of resolving a ticket in this effort, regardless of
`Status`. `HANDOFF.md` already owns that process end to end (build numbering, DMG+ZIP
pairing, signing key). A ticket reaching `ready-for-handoff` means the owner has a local
build to try by hand — nothing more. The owner decides when (and whether) a batch of
`ready-for-handoff` tickets becomes a real release, and does the release themselves
following `HANDOFF.md`.
