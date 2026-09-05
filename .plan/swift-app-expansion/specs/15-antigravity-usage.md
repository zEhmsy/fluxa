# Spec 15 — Antigravity usage

Ticket: `issues/15-antigravity-usage.md`
Author: claude, 2026-09-05
Revised: claude, 2026-09-05 — D2–D5, D7, D8, D10 replaced. The first version read Google's Cloud
Code API with the OAuth token Antigravity stored in the login Keychain. That path shipped in 2.9.0
and returned `403 SUBSCRIPTION_REQUIRED`: `loadCodeAssist` reports the account as `free-tier` with
`UNSUPPORTED_CLIENT` and no `cloudaicompanionProject`, so that API surface is closed to this client
on the individual tier. The credential half of the design is therefore removed, not amended.

Add Antigravity as a third provider in the agent usage strip, beside Claude and Codex. Four quota
meters, read from the helper process Antigravity itself runs.

## D1 — Scope: quota meters only

Four `AgentUsageMetric` values and nothing else.

Excluded, deliberately: local token history (Antigravity's "spend" / "usage trend"). Those numbers
exist only as generation-accounting protobuf records inside
`~/.gemini/antigravity-cli/conversations/*.db`. Fluxa's `AgentLogScanner` reads JSONL session
logs and has no SQLite or protobuf machinery; adding both to serve one provider's charts is a
larger piece of work than the quota reader itself. `AgentUsageWindowView` already tolerates a
provider with no `dailyTokens` entry — the contribution grid is simply omitted — so the provider
degrades cleanly. Revisit as its own ticket if wanted.

## D2 — The source is Antigravity's own helper, not a credential

Antigravity keeps a `language_server` process alive for the whole session and drives its own usage
panel through it over loopback. That process already holds the signed-in session, so Fluxa asks it
the same question:

```
POST http://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary
Content-Type: application/json
x-codeium-csrf-token: <token>
{}
```

This is strictly better than the credential path it replaces, on every axis that matters here:
Fluxa reads no Keychain item, holds no copy of the user's login, derives, caches and refreshes no
token, needs no OAuth client, and the request never leaves the machine. There is consequently
nothing to consent to and nothing to keep in sync with a logout.

The cost is that quota exists only while Antigravity is running (D8).

## D3 — Discovering where to ask

Both facts come from the running process, never from a fixed port or a file on disk.

- `ps -axww -o pid=,command=`. A line is Antigravity's helper when its executable path ends in
  `/language_server` **and** it carries `--app_data_dir antigravity`. That second condition is not
  optional: other editors are built on the same helper and run their own copy, and reading a
  neighbouring product's session would report the wrong numbers under Antigravity's mark.
- The token is the value after `--csrf_token` on that same line.
- `lsof -nP -aiTCP -sTCP:LISTEN -p <pid>` for its listening sockets, keeping `127.0.0.1` only.

Taking the port from that pid's own sockets — rather than probing a guessed port — is what makes
the token safe to send: it can only ever reach the process we identified. `lsof`'s exit status is
ignored, since "nothing found" is reported as a failure and simply means no ports.

The helper is launched with `--https_server_port 0`, so the port differs every run and the cached
value must be re-discovered whenever a request stops working.

## D4 — Trying the ports, and validating the token

The helper holds more than one listening socket and only one of them serves this RPC in the clear.
Which is which is not stated anywhere, so the working one is found by asking: POST to each in the
order reported and stop at the first `2xx`. In practice the other answers `400`, which is enough to
tell "Antigravity is up" from "Antigravity is closed".

The token is validated before use rather than trusted for where it came from: non-empty, at most
256 characters, and alphanumerics plus `-._~` only. It goes into an HTTP header, and a value
carrying a newline would let anything able to influence that command line append headers of its
own.

Cache the endpoint that answered, in memory only. A refresh cycle then costs one loopback request
instead of two process spawns, and nothing is written to disk — the token belongs to a process that
will be gone by the next launch. On any failure, invalidate and re-discover once before giving up:
that is what covers Antigravity being restarted.

Responses over 1 MiB are refused rather than parsed. The real reply is about 1.3 KB; anything near
the cap is not the endpoint we think we are talking to.

## D5 — Rejected: the direct Google call

`POST /v1internal:retrieveUserQuotaSummary` on `cloudcode-pa.googleapis.com` is the same host and
path the helper itself uses, and it is the design this spec originally specified. It is rejected
because it returns `403 SUBSCRIPTION_REQUIRED` for an individual free-tier account, and because
even where it worked it would require holding the user's credential to do what the local call does
with none.

Also excluded, as before: the legacy `fetchAvailableModels` / `retrieveUserQuota` endpoints. They
only serve builds too old for the summary, report 5-hour windows only, and fabricate "fully used"
for models with missing quota data. An older build gets a plain message telling the user to update
Antigravity (D8), which is honest and actionable.

## D6 — Response shape and metric mapping

Accept both `{"groups": …}` and an LS-style `{"response": {"groups": …}}` envelope, since the
latter costs one optional field. Each group carries `buckets`, each bucket a `bucketId`,
a `remainingFraction` (0…1, where **1 means full**) and an ISO-8601 `resetTime`.

Match buckets by **exact `bucketId` only** — never infer a pool from a display name or window, so
a future `gemini-image-5h` cannot silently join a pool and misreport it:

| `bucketId` | Metric id | Label |
|---|---|---|
| `gemini-5h` | `antigravity.session` | Session |
| `gemini-weekly` | `antigravity.weekly` | Weekly |
| `3p-5h` | `antigravity.claude` | Claude |
| `3p-weekly` | `antigravity.claudeWeekly` | Claude Weekly |

Gemini Pro and Flash draw on one shared pool, hence one meter per window rather than one per
model. Every non-Gemini model (Claude, GPT-OSS, …) shares the second pool — which is what `3p`
("third party") names.

`providerID` is `antigravity`, `providerName` is `Antigravity`.

`percentUsed = clamp(0…100, round((1 - remainingFraction) × 100))`, and `resetsAt` is the parsed
`resetTime`. Note the inversion: the API reports what is **left**, `AgentUsageMetric` stores what
is **used**. Getting this backwards is the single most likely bug in the ticket and the tests must
pin it.

Decode leniently: one malformed bucket must not void the envelope, and a bucket whose
`remainingFraction` is missing or non-finite **drops its meter** rather than inventing 0% or 100%.
An undecodable body, or one with no `groups` at all, is an error (D8) — not an empty success,
which would blank a strip that had good numbers a minute ago.

On the label choice: "Claude" as a row under the Antigravity mark, next to the real Claude
provider, is momentarily confusing. It is still the right name — it is what the pool predominantly
is, it is what Antigravity's own UI calls it, and the provider mark to its left disambiguates. The
alternative ("3P", "Other models") trades a moment's confusion for permanent jargon.

## D7 — Where the code lives

Pure logic in `FluxaCore` so it is testable without a running Antigravity; I/O in `Sources/Fluxa`
beside the existing readers.

| File | Contents |
|---|---|
| `Sources/FluxaCore/Services/AntigravityQuota.swift` | quota-summary JSON → `[AgentUsageMetric]`. No AppKit, no Security, no URLSession. |
| `Sources/FluxaCore/Services/AntigravityLocalServer.swift` | *new.* `ps` output → pid + token; `lsof` output → loopback ports; token validation. Pure functions over the text the tools print. |
| `Sources/Fluxa/Services/AntigravityUsageReader.swift` | `fetch()` orchestration: cached endpoint, discovery, the loopback POST, mapping, error classification. Spawns the two tools. |
| `Sources/Fluxa/Services/AgentUsageService.swift` | third `async let` in `performRefresh()`. |
| `Sources/Fluxa/Views/ControlDeckTheme.swift` | `agentIdentity(for:)` — `"antigravity"`. |
| `Sources/Fluxa/Views/AgentUsageWindowView.swift` | `tint(for:)` — `"antigravity"`. |
| `Tests/FluxaCoreTests/AntigravityQuotaTests.swift` | metric mapping. |
| `Tests/FluxaCoreTests/AntigravityLocalServerTests.swift` | *new.* discovery parsing, against fixtures shaped like real tool output. |

Nothing is added to `AgentCredentials.swift`, `PermissionsService.swift` or `PermissionsSetupView.swift`:
there is no credential to read and no permission to grant. `build.sh` ships no extra resource.

`FluxaCore` must stay AppKit-free — ticket 09 established that and it is checked.

## D8 — Errors

Reuse `AgentUsageReadError`; the strip already omits a provider that failed and `AgentUsageService`
keeps the other agents' numbers. One case is added, because none of the existing ones is honest
about this provider's main failure mode:

| Condition | Message |
|---|---|
| Helper not found | `Antigravity: not running. Open Antigravity to show its quota.` |
| Ports found, none served the RPC | `Antigravity: usage is temporarily unavailable. Try again shortly.` |
| 2xx with no `groups` | `Antigravity: this build doesn't report quota summaries yet. Update Antigravity.` |

"Not running" is deliberately distinct from a login problem: there is nothing to sign in to and
nothing to wait for, so neither "sign in again" nor "try again shortly" would be true. Never log or
interpolate the CSRF token into any of these.

## D9 — Independent expression

The interface facts in this spec (the RPC name, the header, the launch flags, the payload shape,
the bucket ids) are facts about how Antigravity's own components talk to each other and carry no
notice obligation, so Fluxa ships no attribution for them. That holds only so long as the
**expression** here is Fluxa's own.

Concretely, this file is the contract: implement from it and from the readers already in
`Sources/Fluxa/Services/`, not from any other implementation of the same integration. The
decomposition (D7) deliberately follows `ClaudeUsageReader` — pure parsing in `FluxaCore`, one
reader struct doing I/O — rather than a provider/client/mapper split. Error taxonomy reuses
`AgentUsageReadError`. Comments explain Fluxa's reasoning.

## D10 — No consent gate

The first version needed one: reading a Keychain item raises a macOS authorisation dialog, so the
background refresh loop had to be prevented from prompting. Reading a local process's quota raises
no dialog and exposes no credential, so the gate, its approval key and its setup card are all
removed rather than left in place doing nothing — a permission card that asks for Keychain access
the app no longer uses is worse than none.

Spawning `ps` and `lsof` requires an unsandboxed app, which Fluxa already is (`ShellRunner`).

## Concurrency

`AntigravityQuota` and `AntigravityLocalServer` are pure and `Sendable`. The reader is a `struct`
doing `async` work off the main actor, matching `ClaudeUsageReader`; only `AgentUsageService` is
`@MainActor`. The endpoint cache is an `actor`, so overlapping refreshes can't race on it.
Discovery blocks on two child processes, so it runs in a detached task rather than on the
cooperative pool the rest of the app shares. Must compile clean under
`-strict-concurrency=complete` for the new files.

## Acceptance

1. With Antigravity running, up to four meters appear under the Antigravity mark, pinnable in
   Customize and rendered in the menu bar strip.
2. Percentages are *used*, not remaining — a nearly-untouched pool reads low, not high, and matches
   what Antigravity's own usage panel shows.
3. With Antigravity closed, the provider reports "not running" and Claude and Codex are unaffected.
4. Quitting and relaunching Antigravity — which changes the port and the token — recovers on the
   next refresh cycle with no user action.
5. No Keychain prompt appears at any point, and Fluxa's Keychain access list gains no entry.
6. A steady state costs one loopback request per refresh: the process table is scanned only after a
   request fails.
7. Each failure produces its own message in Customize; Claude and Codex meters are unaffected by
   any Antigravity failure.
8. `swift test` passes, covering: fraction inversion and rounding; clamping of out-of-range and
   non-finite fractions; unknown/duplicate/malformed buckets; both envelope shapes; missing
   `groups`; helper identification against sibling products and impostor paths; token validation
   including header-injection attempts; port parsing including non-loopback and out-of-range.
9. `FluxaCore` still imports no AppKit. New files compile clean under strict concurrency.
10. `./build.sh` succeeds with `-warnings-as-errors`.
