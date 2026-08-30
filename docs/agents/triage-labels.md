# Triage Labels

The Matt Pocock engineering skills speak in terms of five canonical triage roles. This
effort uses a pipeline vocabulary instead, because a ticket's state is really "which of
the three agents holds it right now". This file maps the canonical roles onto the
pipeline states so the skills stay usable unchanged.

The label lives on a `Status:` line near the top of each file in
`.plan/swift-app-expansion/issues/`.

## The vocabulary

| Status                  | Held by     | Meaning                                                        |
| ----------------------- | ----------- | -------------------------------------------------------------- |
| `spec-pending`          | Claude      | Behaviour identified upstream, no spec written yet              |
| `codex-active`          | Codex       | Spec is complete and approved; Swift implementation in progress |
| `antigravity-validation`| Antigravity | Code exists; tests, fuzzing, benchmarks and concurrency checks running |
| `ready-for-handoff`     | human       | Validated end to end; ready for review, merge and `/handoff`    |
| `needs-info`            | human       | Blocked on a decision only the owner can make                   |
| `wontfix`               | —           | Evaluated and deliberately not ported                           |

Movement is normally forward through the first four. Any state may fall back to
`needs-info`, and any state may terminate at `wontfix`. A failed validation sends the
ticket back to `codex-active`, not to `spec-pending`, unless the spec itself was wrong —
in which case say so explicitly in `## Comments` and reset to `spec-pending`.

## Mapping from the canonical roles

| Label in mattpocock/skills | Label in this repo       |
| -------------------------- | ------------------------ |
| `needs-triage`             | `spec-pending`           |
| `needs-info`               | `needs-info`             |
| `ready-for-agent`          | `codex-active`           |
| `ready-for-human`          | `ready-for-handoff`      |
| `wontfix`                  | `wontfix`                |

`antigravity-validation` has no canonical counterpart; it is an extra stage this effort
inserts between "an agent implemented it" and "a human should look".

When a skill mentions a role — e.g. "apply the AFK-ready triage label" — use the
right-hand string from this table.
