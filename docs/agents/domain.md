# Domain Docs

How the engineering skills should consume this repo's domain documentation when
exploring the codebase. Fluxa is a **single-context** repo: one `CONTEXT.md` and one
`docs/adr/` at the root.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — the glossary of Fluxa's domain terms.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.
- **`HANDOFF.md`** at the repo root — session state and standing rules (release process,
  Sparkle updater, build numbering). It is not a domain doc, but it carries hard
  constraints that override a plausible-looking change.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't
suggest creating them upfront. `/domain-modeling` creates them lazily when terms or
decisions actually get resolved.

## File structure

```
/
├── CONTEXT.md
├── HANDOFF.md
├── docs/
│   ├── adr/
│   │   └── 0001-<slug>.md
│   └── agents/            ← this directory: tracker, labels, roles
└── Sources/Fluxa/
```

This is a single Swift package with one executable target. There is no `CONTEXT-MAP.md`
and no per-context ADR directory; don't create either unless the package is split into
multiple targets or modules.

## Use the glossary's vocabulary

When your output names a domain concept — an issue title, a refactor proposal, a
hypothesis, a test name, a Swift type name — use the term as defined in `CONTEXT.md`.
Don't drift to synonyms the glossary avoids.

This matters more than usual here, because this effort ports behaviour from an external
repo (`vorssaintapp/vorssaint-utils`) that has its own naming. **Upstream names are not
automatically Fluxa names.** When porting, record the mapping in `CONTEXT.md` rather than
importing the upstream vocabulary wholesale. If the concept you need isn't in the
glossary yet, that's a signal: either you're inventing language the project doesn't use
(reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently
overriding:

> _Contradicts ADR-0007 (single UpdateService), but worth reopening because…_

The standing rules in `HANDOFF.md` are stronger than ADRs: treat a contradiction there as
a blocker, set the ticket to `needs-info`, and ask.
