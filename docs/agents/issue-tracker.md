# Issue tracker: Local Markdown

Issues and specs for the Swift app expansion effort live as markdown files under
`.plan/swift-app-expansion/`. There is no GitHub Issues workflow for this effort — do
not call `gh issue`. The GitHub remote (`zEhmsy/fluxa`) is used for code only.

## Layout

```
.plan/swift-app-expansion/
├── map.md                     ← the effort map: notes, decisions so far, open fog
├── specs/
│   └── <NN>-<slug>.md         ← specs authored by Claude via /to-spec
└── issues/
    └── <NN>-<slug>.md         ← one file per ticket, numbered from 01
```

## Conventions

- One effort per directory under `.plan/`. This effort is `swift-app-expansion`.
- The spec for a ticket is `.plan/swift-app-expansion/specs/<NN>-<slug>.md`, sharing the
  ticket's number. A ticket without a matching spec file is by definition `spec-pending`.
- Implementation tickets are one file per ticket at
  `.plan/swift-app-expansion/issues/<NN>-<slug>.md`, numbered from `01`.
  Never a single combined tickets file.
- Triage state is a `Status:` line near the top of each issue file. See
  `docs/agents/triage-labels.md` for the exact strings.
- Each ticket also carries an `Owner:` line naming the executor
  (`claude` / `codex` / `antigravity`). See `docs/agents/roles.md`.
- Comments and conversation history append to the bottom of the file under a
  `## Comments` heading, newest last, each entry prefixed with the author.

## Ticket frontmatter

Every issue file opens with this block, before the first heading body:

```markdown
# NN — <title>

Status: spec-pending
Owner: claude
Type: task
Spec: specs/NN-<slug>.md
Blocked by: —
Source: vorssaint-utils <path or symbol being ported>
```

`Source:` is specific to this effort. It records where the *idea* came from, and asserts
that no third-party code was consulted. For clean-room tickets it reads:

```
Source: clean-room. Feature idea only. No upstream code read.
```

Use `—` for work with no external inspiration at all. **Never** put a path or a symbol
from another project here — see the clean-room rule below.

## Clean-room rule (binding)

This effort was re-scoped after ticket `01`: `vorssaintapp/vorssaint-utils` is GPL-3.0 and
Fluxa is Apache-2.0, so nothing may be ported. Feature *ideas* are not copyrightable and
are fair game; source code is not.

While working any ticket in this effort:

- Do not read, fetch, clone, or quote source from `vorssaint-utils` or any other GPL
  codebase.
- Derive every design decision from Fluxa's own code, Apple's documentation, and the
  ticket text.
- A Swift-to-Swift retranscription is still a derivative work. Rewriting is not laundering.
- If a ticket seems to require looking at someone else's implementation, set
  `Status: needs-info` and say so. Do not look.

## When a skill says "publish to the issue tracker"

Create a new file under `.plan/swift-app-expansion/issues/`, taking the next free number.
Creating the directory if needed.

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user normally passes the path or the number
directly; `03` means `.plan/swift-app-expansion/issues/03-*.md`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is `map.md` with one **child** file per ticket.

- **Map**: `.plan/swift-app-expansion/map.md` (Notes / Decisions-so-far / Fog).
- **Child ticket**: `issues/NN-<slug>.md`. `Type:` records `research`/`prototype`/`grilling`/`task`.
- **Blocking**: a `Blocked by: NN, NN` line. A ticket is unblocked when every file it
  lists has reached `ready-for-handoff` (or `wontfix`).
- **Frontier**: scan `issues/` for files that are open, unblocked, and unclaimed;
  lowest number wins.
- **Claim**: set `Owner:` to the agent taking it and advance `Status:` before any work.
- **Resolve**: append the outcome under an `## Answer` heading, set
  `Status: ready-for-handoff`, then append a context pointer to Decisions-so-far in `map.md`.
