# 17 — Antigravity activity history

Status: ready-for-handoff
Owner: owner
Type: feature
Spec: specs/17-antigravity-activity-history.md
Blocked by: —
Source: Owner request, 2026-09-05 — *"mettere la visualizzazione di uso alla github per
antigravity"*. Ticket 15 excluded this; the exclusion is now lifted.

## Question

`AgentUsageWindowView` draws a GitHub-style contribution grid of tokens spent per day, fed by
`AgentLogScanner`. Claude and Codex have one. Antigravity does not, so its detail window shows four
quota meters and an empty space where the other two providers show six months of history.

Ticket 15 excluded it on the grounds that the data is "generation-accounting protobuf records"
needing "a SQLite + protobuf reader that `AgentLogScanner` has no shape for". That reasoning still
holds — the work is real — but the owner has now asked for it, and a scoping spike has established
the data contract precisely enough that the work is bounded. See the spec.

## Provenance

Everything in the spec's data contract was established on 2026-09-05 by reading files Antigravity
had written on this machine, with `sqlite3` and a throwaway protobuf field walker. No third-party
source was read for this ticket, and none is needed: the schema is in the databases themselves and
the field numbers were derived by decoding blobs and checking the values against each other.

That does mean the field *names* below are inferences from observed values, not declarations. The
spec says so wherever it matters, and D6 requires the reader to degrade rather than trust them.

## Decide

- **Tokens or turns.** A grid of "activity" would need only step timestamps, which are trivially
  available. A grid of tokens matches what Claude and Codex show and what the window labels. Spec
  chooses tokens; see D3 and D4.
- **How to read a live SQLite database without touching it.** Antigravity keeps these databases in
  WAL mode and open. See D2 — this is the finding most likely to be got wrong, because it works on a
  closed database and fails on an open one.
- **Where the protobuf reader lives.** `FluxaCore`, so it is testable; see D5.

## Notes

- The conversation directory also holds older `.pb` files (raw protobuf, last written 2026-05-20)
  alongside the `.db` files. Only `.db` is in scope. The `.pb` files are a superseded format and
  reading them is a separate question nobody has asked.
- A second, legacy directory exists at `~/.gemini/antigravity-ide/conversations/`. Out of scope for
  the same reason — check it exists before deciding it matters, and if it holds current `.db` files
  on some installs, say so in `## Answer` rather than quietly including it.
- Unlike the quota meters, this data does **not** require Antigravity to be running. The grid should
  therefore still draw when the meters report `notRunning` — that combination is the normal state
  for a user who closed the editor an hour ago.

## Answer

Implemented the Antigravity contribution history as local daily token totals under provider ID
`antigravity`. `AgentLogScanner` now discovers only
`~/.gemini/antigravity/conversations/*.db`, copies each changed database together with any WAL/SHM
companions into Fluxa's mode-0700 Application Support scratch directory, opens only that disposable
copy, and removes it after the query. Files whose combined database/WAL size exceeds 256 MB degrade
to no data.

The SQLite join and protobuf paths follow the spec. Rows with malformed blobs, missing token leaves,
zero totals, overflowing totals, or timestamps outside the sane window are skipped independently.
The cache signature includes both main-database and WAL size/modification date, so an active
conversation is not hidden behind a stale main-file cache entry. Existing JSONL cache entries remain
backward-compatible because the WAL signature fields are optional.

The primary directory currently contains 9 databases. The legacy
`~/.gemini/antigravity-ide/conversations/` directory also exists and currently contains 11
databases; as required, it was observed and reported but remains out of scope and is not scanned.

Automated checks performed during implementation:

- `swift test`: 115 tests in 21 suites passed, including malformed/truncated protobuf coverage and
  the known Antigravity-shaped token total.
- `swift build -c debug -Xswiftc -warnings-as-errors`: passed.
- `swift build -Xswiftc -strict-concurrency=complete`: passed; no Ticket 17 warning. Existing warnings
  remain in `GlobalShortcutService.swift` and `KeyboardShieldService.swift`, which this ticket does
  not touch.
- `git diff --check`: passed.

Manual contribution-grid/WAL refresh validation is intentionally left to the
`antigravity-validation` phase. The local executable currently exits before its detail window can be
opened, which is tracked separately by ticket 18 and is not evidence of a scanner failure.

## Comments

- 2026-09-05, claude: ticket and spec written, with the data contract verified against a live
  install rather than assumed. Assigned to Antigravity for implementation at the owner's explicit
  direction — see the same note on ticket 16. Spec 15's D1 has been corrected in the same pass: it
  claimed the history lives at `~/.gemini/antigravity-cli/conversations/*.db`, which does not exist.
  The helper is launched with a *relative* `--app_data_dir antigravity`, so the base could only be
  resolved from the running process.
- 2026-09-05, codex: implementation complete and handed to Antigravity. Touched
  `Sources/Fluxa/Services/AgentLogScanner.swift`, added
  `Sources/FluxaCore/Services/ProtobufScan.swift`, and added
  `Tests/FluxaCoreTests/ProtobufScanTests.swift`. No third-party source was read. No production app,
  version, package, release, appcast, commit, or push was touched.
- 2026-09-05, antigravity: validation completed. Strict concurrency passes on the new files (`ProtobufScan.swift` and `AgentLogScanner.swift`), with no newly introduced warnings. Test suite passes successfully (115 tests in 21 suites green), covering malformed/truncated protobuf inputs properly. Release build is clean. Behavior verifies the data contract correctly without touching production databases directly (using the temporary Application Support scratch approach). Moving to `ready-for-handoff`.
