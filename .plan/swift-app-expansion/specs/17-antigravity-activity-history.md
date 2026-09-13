# Spec 17 — Antigravity activity history

Ticket: `issues/17-antigravity-activity-history.md`
Author: claude, 2026-09-05

Give Antigravity the same six-month contribution grid Claude and Codex already have, by reading the
conversation databases Antigravity writes locally.

Everything below marked *verified* was observed on 2026-09-05 against a live install on this
machine. Everything marked *inferred* is a reading of values whose declared meaning is not
available; D6 says what to do when an inference turns out wrong.

## D1 — Where the data is

*Verified.* Base directory: `~/.gemini/antigravity/conversations/`.

This corrects spec 15, which guessed `~/.gemini/antigravity-cli/conversations/`. That path does not
exist. The helper process is launched with a **relative** `--app_data_dir antigravity`, so the base
cannot be read off the command line and had to be resolved from the running process's open files.
Do not re-derive it at runtime — hardcode `~/.gemini/antigravity/conversations`, the same way
`AgentLogScanner` hardcodes `~/.claude/projects` and `~/.codex/sessions`.

Take `*.db` only. The directory also contains `*.pb` files, last written 2026-05-20; they are a
superseded format and are out of scope. Ten `.db` files were present, 828 KB to 16 MB.

## D2 — Reading a live database without touching it

*Verified, and the most likely thing to get wrong.*

These databases are **WAL mode** (`pragma journal_mode` → `wal`) and Antigravity holds them open
while it runs. A read-only open fails:

```
$ sqlite3 -readonly .../4ca67e89-….db "select count(*) from steps;"
Error: in prepare, unable to open database file (14)
```

while a normal open of the same file succeeds. SQLite cannot read a WAL database read-only without
being able to create and map the `-shm` segment. This is why the mistake is easy to miss: it works
on every database Antigravity has closed, and fails on the one the user is actively using — which
is the one whose data matters.

Neither escape route is acceptable on its own terms:

- Opening read-write would mean Fluxa writing into Antigravity's files. Not doing that is the same
  standing rule that governs ticket 15's Keychain item, and it is not negotiable.
- `?immutable=1` opens read-only by declaring the file unchanging, which skips the WAL entirely.
  On a database being written that yields a stale or torn read with no error.

**Copy, then read the copy.** For each database that needs scanning, copy `x.db`, `x.db-wal` and
`x.db-shm` (whichever exist) into a Fluxa scratch directory, open the *copy* normally so WAL
recovery can run against files we own, read it, then delete the copy. Antigravity's originals are
opened for reading only, by `FileManager`, and never by SQLite.

The copy is affordable because D7 means it only happens for databases that actually changed. Bound
it anyway: skip any database over 256 MB rather than copying it, and record the skip.

Scratch directory: a subdirectory of `Fluxa`'s existing Application Support directory, created 0700
and emptied at the start of each scan so an interrupted run leaves nothing behind.

## D3 — The two tables, and the join

*Verified.* The relevant schema, of the eight tables present:

```sql
CREATE TABLE `steps` (`idx` integer, `metadata` blob, …, PRIMARY KEY (`idx`));
CREATE TABLE `gen_metadata` (`idx` integer, `data` blob, `size` integer, PRIMARY KEY (`idx`));
```

`steps.metadata` carries the timestamp. `gen_metadata.data` carries the token counts. They are
joined on `idx`: in the sampled database `gen_metadata` had 64 rows and `steps` had 128, and every
`gen_metadata.idx` was present in `steps.idx`. A `gen_metadata` row whose `idx` has no matching
step contributes nothing and is dropped — that is a missing timestamp, not a day to guess at.

Read both tables in one pass:

```sql
SELECT g.idx, g.data, s.metadata FROM gen_metadata g JOIN steps s ON s.idx = g.idx
```

**Timestamp.** *Verified.* `steps.metadata` is protobuf; field `1` is a length-delimited submessage
whose field `1` is a varint of **epoch seconds**. Decoded across all 128 rows of the sample it gave
`2026-09-05 01:29:52` … `2026-09-05 01:35:57`, matching the file's own modification time. It is
shaped exactly like a `google.protobuf.Timestamp`, so field `2` is presumably nanoseconds; ignore
it, seconds are ample for a day bucket.

## D4 — The token fields

*Inferred*, from decoding all 64 `gen_metadata` rows of the sample and comparing the value
distributions. Path notation below is field numbers from the root: `1.4.2` means root field 1,
its field 4, its field 2 — all length-delimited except the leaf, which is a varint.

| Path    | Observed                                    | Read as |
| ------- | ------------------------------------------- | ------- |
| `1.4.1` | `1318` on every row, never varying          | fixed system-prompt tokens |
| `1.4.2` | 2 060 – 82 339, uncorrelated with position  | prompt tokens |
| `1.4.3` | 77 – 8 965                                  | output tokens |
| `1.4.5` | 8 162 – 199 978, rising through the session | cached tokens read |
| `1.4.9` | 14 – 8 895, always ≤ `1.4.3` on the same row | reasoning tokens |

The same five values appear again at `1.17.2.*`, identical row for row. Read `1.4.*`; ignore
`1.17.2.*` rather than averaging or cross-checking — a second copy of the same numbers is not
corroboration.

**Day total** = Σ over rows of `1.4.1 + 1.4.2 + 1.4.3 + 1.4.5`.

`1.4.9` is excluded: it is bounded above by `1.4.3` on every sampled row, so it is a component of
the output count and adding it would double-count. The four that are summed are the analogue of
`AgentLogScanner.scanClaudeFile`'s `input + output + cache_creation + cache_read`, which is what the
window's "tokens" label already means for the other two providers. As with Claude, the total is
dominated by cache reads — 7.1 M of 7.7 M in the sample. That is expected, not a bug.

**Day bucket** = the **local** calendar day of the joined step's timestamp, formatted `yyyy-MM-dd`
with `en_US_POSIX`. Local, not UTC, for the reason already written into
`AgentLogScanner.localDay(fromISO:)`: UTC bucketing moves an evening's work onto the next day for
anyone east of Greenwich. Reuse that formatter; do not add a second one.

## D5 — A minimal protobuf reader, in `FluxaCore`

Add `Sources/FluxaCore/Services/ProtobufScan.swift` — a `package enum` with no state:

- varint decode at an offset, returning value and new offset;
- iterate top-level fields, yielding `(number, wireType, payload)`, correctly skipping wire types
  1 (64-bit) and 5 (32-bit) and stopping cleanly on wire type 3/4 or a malformed key;
- `value(at path: [Int])`, following length-delimited fields to a leaf varint.

It goes in `FluxaCore` because that is the only target `FluxaCoreTests` can import, and this is the
one part of the ticket with enough sharp edges to be worth real tests. It must be AppKit-free and
must **never** trap: every read is bounds-checked and returns `nil` on truncation. A corrupt blob is
an expected input, not a programming error.

SQLite itself stays in the `Fluxa` target (`import SQLite3`), alongside the rest of the scanner.

## D6 — Degrade, do not trust

The field numbers in D4 are inferences and Antigravity will change its format eventually. Every
failure below drops data and continues; none aborts the scan and none crashes:

- a row missing `1.4` entirely, or missing all four summed leaves → skip the row;
- a row whose leaves are present but sum to zero → skip the row, do not record a zero day;
- a `gen_metadata` row with no matching step, or a step with no decodable timestamp → skip;
- a database that will not open, or has no `steps`/`gen_metadata` table → skip the file;
- a timestamp outside a sane window (before 2020, or more than a day in the future) → skip the row.

If a whole scan produces nothing, Antigravity simply has no `dailyTokens` entry, and
`AgentUsageWindowView` already omits the grid for a provider with no entry — spec 15 D1 relied on
exactly that. So the worst case is the behaviour that ships today.

## D7 — Caching, and the WAL trap in it

Reuse `AgentLogScanner`'s existing `CachedFile` mechanism: size plus modification date, keyed by
path, unchanged means reuse without reading a byte.

One correction is required for SQLite. A WAL database's **main file does not change** while writes
accumulate in its `-wal`; a cache keyed on `x.db` alone will serve stale totals for as long as the
user keeps a conversation open. The cache key must therefore fold in the size and modification date
of `x.db-wal` as well, treating an absent `-wal` as zero/`distantPast`.

Antigravity's databases are also mutated in place rather than appended to, so the comment on
`CachedFile` — "logs are append-only, so a file whose size and modification date are unchanged
cannot have new usage in it" — is true for JSONL and not for these. Either widen that comment or
give the SQLite path its own; do not leave a comment asserting something false about the code
beneath it.

## D8 — Wiring

`AgentLogScanner.scan()` gains a third entry:

```swift
totals["antigravity"] = scanAntigravityDatabases()
```

`providerID` must be exactly `"antigravity"`, matching what the quota reader publishes, or the
window will not find the history. `AgentUsageService` maps `DailyTotals` into `dailyTokens` with no
per-provider knowledge, and `AgentUsageWindowView` picks the provider up from
`usage.dailyTokens.filter { !$0.value.isEmpty }.map(\.key)` — so nothing else needs editing.
Confirm `AgentUsageWindowView.tint(for:)` already has an `antigravity` case from ticket 15; it
should, but the grid is the first thing to depend on it.

The scan already runs off the main thread inside the `AgentLogScanner` actor. Keep it there; do not
add a second concurrency mechanism for the SQLite work.

**Do not touch** `AgentUsageReaders.swift`, `AntigravityLocalServer` or anything else on the quota
path. This ticket adds a source of history and changes nothing about the meters — including that
the grid must still draw when the meters report `notRunning`, which is the normal state for a user
who has closed the editor.

## Testing

In `Tests/FluxaCoreTests/ProtobufScanTests.swift`, a Swift Testing suite over `ProtobufScan`:

- single varint field; multi-byte varints; a nested submessage read through `value(at:)`;
- a path that does not exist → `nil`;
- wire types 1 and 5 skipped correctly so a later field is still found;
- **truncation at every byte length of a valid message** — none may trap;
- a leading byte of `0x00` (field number 0) and a wire type of 6/7 → `nil`, no loop;
- a length prefix larger than the remaining buffer → `nil`;
- a hand-built message shaped like D4's `1.4.{1,2,3,5}` summing to a known total.

Then, by hand against the real install, before the ticket moves on:

1. Antigravity's grid appears in the detail window and its six-month total is non-zero.
2. A conversation held open in Antigravity is picked up on the next refresh — this is the D7 WAL
   case and it is the one that will regress silently.
3. Antigravity quit: meters report not running, grid still draws.
4. `~/.gemini/antigravity/conversations/` absent (rename it temporarily): no grid, no error, other
   providers unaffected.
5. Antigravity's originals are byte-identical before and after a scan, and their `-wal`/`-shm` are
   untouched. Check this explicitly — it is D2's whole point.
6. Full suite green, `./build.sh` clean, and no new strict-concurrency warnings beyond the
   pre-existing `vm_kernel_page_size` in `MemorySampler.swift:18`.

Record in `## Answer` the six-month total the grid shows and whether it is plausible against
Antigravity's own usage panel. Exact agreement is not expected — Fluxa is counting local
generation records, not the vendor's billing — but an order-of-magnitude disagreement means D4 is
wrong.
