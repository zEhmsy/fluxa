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
  **Precondition**: the package has no `testTarget` today and `Tests/FluxaScreenshots/`
  is empty, so `swift test` does nothing. Ticket `02` stands one up; until it lands, no
  ticket can leave `antigravity-validation`.
- Edge-case fuzzing: boundary values, malformed input, empty and maximal collections.
  For the sampler tickets specifically: counter wraparound, hardware that reports nothing
  (a desktop Mac has no battery), and devices that disappear mid-sample.
- Performance benchmarks for anything on a sampling or menu-bar refresh path, with a
  recorded baseline so regressions are visible.
- Strict concurrency validation: build with
  `-Xswiftc -strict-concurrency=complete` and report every warning. A ticket does not
  reach `ready-for-handoff` while it introduces new concurrency warnings.
- Verifies the retain-cycle claim rather than trusting it.

**Produces**: tests under `Tests/`, benchmark numbers and a validation verdict in the
ticket's `## Answer` section.
**Does not**: fix the implementation. A failure sends the ticket back to `codex-active`
with a reproducible case.

**Hands off** by setting `Status: ready-for-handoff` — or back to `codex-active` on
failure.

## Escalation

Any agent may set `Status: needs-info` and stop. Do so rather than guessing when a
decision changes the shape of the result, when the spec conflicts with `HANDOFF.md`, or
when upstream behaviour can't be determined from the source.
