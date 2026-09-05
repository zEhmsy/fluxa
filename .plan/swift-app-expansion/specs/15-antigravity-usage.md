# Spec 15 — Antigravity usage

Ticket: `issues/15-antigravity-usage.md`
Author: claude, 2026-09-05

Add Antigravity as a third provider in the agent usage strip, beside Claude and Codex. Four quota
meters, read from Google's Cloud Code API with the OAuth token Antigravity already stored in the
login Keychain.

## D1 — Scope: quota meters only

Four `AgentUsageMetric` values and nothing else.

Excluded, deliberately: local token history (Antigravity's "spend" / "usage trend"). Those numbers
exist only as generation-accounting protobuf records inside
`~/.gemini/antigravity-cli/conversations/*.db`. Fluxa's `AgentLogScanner` reads JSONL session
logs and has no SQLite or protobuf machinery; adding both to serve one provider's charts is a
larger piece of work than the quota reader itself. `AgentUsageWindowView` already tolerates a
provider with no `dailyTokens` entry — the contribution grid is simply omitted — so the provider
degrades cleanly. Revisit as its own ticket if wanted.

## D2 — Credentials come from the Keychain, read-only

Generic-password item, service `gemini`, account `antigravity`, written by the Antigravity app or
the `agy` CLI.

The value is a `go-keyring-base64:`-prefixed base64 wrapper around JSON. Unwrap the prefix, decode,
then read from the nested `token` object (falling back to the root):

| Field | Keys accepted |
|---|---|
| access token | `access_token`, `accessToken` |
| refresh token | `refresh_token`, `refreshToken` |
| expiry | `expiry`, `expires_at`, `expiresAt` — ISO-8601 |

Accept a bare JSON string or a raw `Bearer …` value as an access token with no refresh token, so a
format change degrades to "expires and can't refresh" rather than "provider vanished". Never treat
malformed structured material (text starting `{` or `[` that failed to parse) as a bearer token.

Add `AgentCredentialStore.loadAntigravity(requestAccess:)` alongside `loadClaude` / `loadCodex`.
The store's read-only stance holds: **Fluxa never writes to Antigravity's Keychain item.**

## D3 — The refresh exception (the decision that matters)

`AgentCredentialStore`'s doc comment explains why it never refreshes: Claude and Codex rotate the
refresh token on use, so renewing behind their back would invalidate the login the owning CLI
holds. That reasoning is about *rotation*, not about refresh in principle.

Google's refresh-token grant does **not** rotate the refresh token. Exchanging it yields a new
access token and leaves Antigravity's stored credential untouched and still valid. So the
invariant Fluxa actually cares about — *never break the owning tool's login* — is preserved by
refreshing, provided we never write back. Narrow the rule accordingly, in the code comment as well
as here:

> Read-only means Fluxa never modifies another tool's stored credential. Deriving a short-lived
> access token from a non-rotating refresh token, and caching it somewhere of our own, does not
> modify it.

Mechanics:

- `POST https://oauth2.googleapis.com/token`, form-encoded,
  `grant_type=refresh_token` with the installed-application client pair (D4).
- Cache the derived access token at
  `~/Library/Application Support/Fluxa/antigravity/auth.json` — **Fluxa's own file**, so a refresh
  costs one exchange per token lifetime instead of one per refresh cycle.
- Bind the cache to `SHA256(refreshToken)` stored beside it. On load, require the fingerprint to
  match the *current* Keychain credential. A logout, an account switch, or a cache file that
  predates the fingerprint field is a miss, and the file is discarded. This is what stops a
  previous account's token being replayed after the user signs in as someone else.
- Treat a token with under 60s of life left as already expired.
- Classify the refresh outcome three ways, because the user-facing message differs:
  `4xx` (except 408/429) = sign-in expired; `408`/`429`/`5xx`/transport = temporarily unavailable;
  `2xx` but undecodable = temporarily unavailable. A dead refresh token must not be reported as a
  network blip, and a network blip must not tell the user to sign in again.

## D4 — OAuth client credentials

The refresh grant runs under Google **installed-application** client credentials that ship inside
every copy of the Antigravity app. Google does not treat such a secret as confidential — it cannot
be, being distributed to every user — but it is not ours either, and a copy of it in a public
repository is precisely what gets a client rotated, which would break this provider for everyone.

So the values live in `packaging/antigravity-client.json`, ignored by git, and `build.sh` copies
that file into `Contents/Resources/antigravity-client.json` at packaging time. The reader loads it
from the bundle. `packaging/antigravity-client.json.example` documents the shape.

When the file is absent the provider still reads quota with whatever access token Antigravity
already stored; only the refresh path is lost, so a source-only build degrades to "sign in again"
rather than failing. Not a credential of the user's, and never logged.

## D5 — One endpoint, no legacy fallback

`POST /v1internal:retrieveUserQuotaSummary`, JSON in and out, `Authorization: Bearer <token>`.

Base URLs tried in order — `https://daily-cloudcode-pa.googleapis.com`, then
`https://cloudcode-pa.googleapis.com`. Both serve the endpoint and this order is known to work in
the field, so there is no evidence for preferring the other; a `401`/`403` short-circuits (the same
token would fail on the other base too), while any other non-2xx or transport failure falls through
to the next base and finally to "unavailable".

Excluded: the local language-server RPC and the two legacy endpoints
(`fetchAvailableModels` / `retrieveUserQuota`). The language server would need process scanning
for `language_server`/`agy`, a CSRF token, a port sweep and a loopback session trusting a
self-signed certificate — a lot of surface whose only gain over the Keychain path is the plan-tier
label. The legacy endpoints only serve builds too old for the summary, report 5-hour windows
only, and fabricate "fully used" for models with missing quota data. Both are worth skipping for a
first version. An older build therefore gets a plain message telling the user to update
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

Pure logic in `FluxaCore` so it is testable without a Keychain or a network; I/O in `Sources/Fluxa`
beside the existing readers.

| File | Contents |
|---|---|
| `Sources/FluxaCore/Services/AntigravityQuota.swift` | *new.* Keychain-blob → tokens, and quota-summary JSON → `[AgentUsageMetric]`. No AppKit, no Security, no URLSession. |
| `Sources/Fluxa/Services/AntigravityUsageReader.swift` | *new.* `fetch()` orchestration: load credential, use or refresh, call Cloud Code, map, classify errors. Owns the derived-token cache file. |
| `Sources/Fluxa/Services/AgentCredentials.swift` | `loadAntigravity(requestAccess:)`, its own approval key. |
| `Sources/Fluxa/Services/AgentUsageService.swift` | third `async let` in `performRefresh()`. |
| `Sources/Fluxa/Views/ControlDeckTheme.swift` | `agentIdentity(for:)` — add `"antigravity"`. |
| `Sources/Fluxa/Views/AgentUsageWindowView.swift` | `tint(for:)` — add `"antigravity"`. |
| `Sources/Fluxa/Services/PermissionsService.swift` | `antigravity` status + `requestAntigravityAccess()`. |
| `Sources/Fluxa/Views/PermissionsSetupView.swift` | consent row, mirroring Claude's. |
| `Tests/FluxaCoreTests/AntigravityQuotaTests.swift` | *new.* |

`FluxaCore` must stay AppKit-free — ticket 09 established that and it is checked.

## D8 — Errors

Reuse `AgentUsageReadError` where it fits; the strip already omits a provider that failed and
`AgentUsageService` keeps the other agents' numbers. Messages, all naming the agent:

| Condition | Message |
|---|---|
| No Keychain item | `Antigravity: not signed in. Open Antigravity or run `agy` to sign in.` |
| Keychain read failed / denied | `Antigravity: couldn't read credentials from Keychain. Unlock Keychain or sign in again.` |
| Blob malformed | `Antigravity: stored credentials are unreadable. Sign in again.` |
| Refresh returned 4xx | `Antigravity: sign-in expired. Open Antigravity or run `agy` to refresh.` |
| Both bases unavailable | `Antigravity: usage is temporarily unavailable. Try again shortly.` |
| 2xx with no `groups` | `Antigravity: this build doesn't report quota summaries yet. Update Antigravity.` |

Never log or interpolate a token, a refresh token, or the raw Keychain blob into any of these.

## D9 — Independent expression

The interface facts in this spec (Keychain item, endpoint, payload shape, bucket ids, OAuth client)
are facts about Google's service and carry no notice obligation, so Fluxa ships no attribution for
them. That holds only so long as the **expression** here is Fluxa's own.

Concretely, this file is the contract: implement from it and from the readers already in
`Sources/Fluxa/Services/`, not from any other implementation of the same integration. The
decomposition below (D7) deliberately follows `ClaudeUsageReader` + `AgentCredentialStore` —
pure parsing in `FluxaCore`, one reader struct doing I/O — rather than a provider/client/mapper
split. Error taxonomy reuses `AgentUsageReadError`. Comments explain Fluxa's reasoning.

## D10 — Consent, and never prompting from a timer

Reading the Keychain item raises a macOS authorisation dialog. `AgentCredentialStore` already
solved this for Claude and the same shape applies, with a **separate** approval key so consenting
to one agent never implies the other:

- Ordinary refreshes pass `requestAccess: false` and use a non-interactive `LAContext`; without a
  recorded approval they throw `approvalNeeded` before touching the Keychain.
- Only the setup button passes `requestAccess: true`.
- The approval is keyed to the current code-signing requirement, so a re-signed or ad-hoc build
  cannot inherit consent and start prompting from the background loop.
- A denied read clears the approval and does not retry in a prompt loop.

`AgentUsageService.startAutoRefresh` already makes no request at all when no agent is pinned, so
an install that ignores this feature is never prompted.

## Concurrency

`AntigravityQuota` is pure and `Sendable`. The reader is a `struct` doing `async` work off the main
actor, matching `ClaudeUsageReader`; only `AgentUsageService` is `@MainActor`. The derived-token
cache is written from the reader's task — keep the read/modify/write inside a single `actor` or
behind the existing `AgentCredentialStore.readLock` so two concurrent refreshes can't interleave a
half-written file. Must compile clean under `-strict-concurrency=complete` for the new files.

## Acceptance

1. With Antigravity signed in and consent granted, up to four meters appear under the Antigravity
   mark, pinnable in Customize and rendered in the menu bar strip.
2. Percentages are *used*, not remaining — a nearly-untouched pool reads low, not high.
3. With Antigravity closed, the meters still refresh (Keychain + Cloud Code path).
4. An expired access token refreshes once, is cached, and the next refresh cycle performs no
   second OAuth exchange.
5. After signing out and back in as a different account, no cached token from the previous account
   is ever used.
6. Antigravity's own Keychain item is byte-identical before and after a full refresh cycle.
7. Without consent, no Keychain prompt appears from the background refresh loop.
8. Each failure in D8 produces its own message in Customize; Claude and Codex meters are
   unaffected by any Antigravity failure.
9. `swift test` passes, covering: fraction inversion and rounding; clamping of out-of-range and
   non-finite fractions; unknown/duplicate/malformed buckets; both envelope shapes; missing
   `groups`; `go-keyring-base64` unwrapping; nested vs root token objects; expiry parsing.
10. `FluxaCore` still imports no AppKit. New files compile clean under strict concurrency.
11. `./build.sh` succeeds with `-warnings-as-errors`.
