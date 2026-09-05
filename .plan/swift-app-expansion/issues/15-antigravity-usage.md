# 15 — Antigravity usage

Status: ready-for-handoff
Owner: owner
Type: task
Spec: specs/15-antigravity-usage.md
Blocked by: —
Source: Antigravity / Google Cloud Code interface facts — Keychain item, endpoint path, payload
shape — established while scoping this ticket. No third-party source code copied.

## Question

Fluxa's agent usage strip reads Claude and Codex quotas today. Antigravity — Google's AI IDE,
which this effort already uses as its validation agent — has quota windows too, and its mark
(`Resources/AgentIcons/antigravity.pdf`) is already in the bundle. Add it as a third provider.

## Provenance — read before working this ticket

This ticket is **not** clean-room, and must not be recorded as one. Scoping it involved reading a
third-party, permissively-licensed implementation of the same integration to establish how
Antigravity's quota is exposed. What that produced is a set of **interface facts about Google's
service** — a Keychain service/account pair, an HTTPS path, JSON field names, four bucket
identifiers, an installed-application OAuth client pair. Facts about someone else's interface carry
no copyright, and no notice obligation attaches to them.

What this means for whoever works the ticket:

- **Nothing is transcribed.** The reader is written against Fluxa's own shapes — it mirrors
  `ClaudeUsageReader` and `AgentCredentialStore`, which is a different decomposition from the
  reference. Structure, naming, error taxonomy and comments must come from this codebase.
- The clean-room rule in `docs/agents/issue-tracker.md` still binds absolutely for GPL sources.
  It is not what governed this ticket, and this section exists so no future reader assumes it was.
- If a design question can only be answered by looking at someone else's implementation again,
  that is a signal the spec is underspecified — fix the spec, don't copy.

## Decide

- **How much of the provider to build.** The full integration has several sources (a local
  language server, a Cloud Code quota-summary endpoint, two legacy Cloud Code endpoints) plus a
  local SQLite/protobuf conversation scanner for token history. Spec cuts this to the one
  authoritative source; see D1 and D5.
- **The read-only exception.** `AgentCredentialStore` is deliberately read-only, because
  refreshing Claude's or Codex's token would invalidate the copy the owning CLI holds. Antigravity
  *requires* a refresh: its Keychain access token expires and only a Google OAuth exchange renews
  it. Resolved in D3 — refresh, never write back — and this is the decision that most needs the
  owner's eyes.
- **Keychain consent.** Reading Antigravity's Keychain item raises a macOS prompt exactly as
  Claude's does, so it needs the same explicit opt-in and the same "never prompt from a timer"
  guarantee. See D10.

## Notes

- Requires macOS Keychain item service `gemini`, account `antigravity`, written by the Antigravity
  app or the `agy` CLI. Absent that, the provider reports "not signed in" and no other agent is
  affected — `AgentUsageService` already isolates per-agent failures.
- Only newer Antigravity builds serve the quota-summary endpoint. Older ones get a clear
  "update Antigravity" message rather than a fallback; D5 explains why that trade is worth it.
- The metric marks load by `providerID` at runtime, so `antigravity.pdf` needs no registration.
  Two colour switches do need a new case and are easy to miss:
  `ControlDeckTheme.agentIdentity(for:)` and `AgentUsageWindowView.tint(for:)`.

## Answer

Validation performed 2026-09-05 by Antigravity.

**Verdict: FAILED — returned to `codex-active` with reproducible crash defect.**

### 1. Fuzzing & Unprotected Arithmetic Analysis
- `percentUsed(remainingFraction:)`: Confirmed fixed. Clamping in `Double` space before `Int` conversion prevents integer overflow traps on extreme finite values (`-1e300`, `1e300`, `-.greatestFiniteMagnitude`, `.greatestFiniteMagnitude`, subnormals).
- **CRITICAL DEFECT — Unprotected Arithmetic & Server-Triggered App Crash**:
  In `AntigravityQuota.swift:204`:
  ```swift
  private static func expiry(_ value: Any?) -> Date? {
      if let text = trimmed(value as? String) {
          return iso8601(fractionalSeconds: true).date(from: text)
              ?? iso8601(fractionalSeconds: false).date(from: text)
      }
      guard let number = number(value), number.isFinite else { return nil }
      return Date(timeIntervalSince1970: abs(number) < 1e10 ? number : number / 1000)
  }
  ```
  While `lifetime` in `AntigravityUsageReader.swift` was defensively clamped to `min(max(raw, 0), 3600)`, `AntigravityQuota.expiry` places no upper bound on `number`. An extreme finite `resetTime` received from the quota endpoint (e.g. `1e300` or any value > `~9.22e21` ms / `~9.22e18` s) creates a `Date` representing year 10^290.
  When `AgentUsageMetric.resetNote()` is subsequently called in the UI (`AgentUsageStripView.swift:127`, `ControlDeckMetricsView.swift:221`, or `AgentUsageWindowView.swift:165`):
  ```swift
  package func resetNote(now: Date = Date()) -> String? {
      guard let resetsAt, resetsAt > now else { return nil }
      let seconds = Int(resetsAt.timeIntervalSince(now)) // <--- CRASH HERE
  ```
  `resetsAt.timeIntervalSince(now)` exceeds `Double(Int.max)`. Converting to `Int` traps on arm64:
  `Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max`
  This raises `SIGTRAP` (signal 5) and crashes the entire Fluxa application.
  **Reproducible test case**:
  ```swift
  let json = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.5,"resetTime":1e300}]}]}"#
  let metrics = AntigravityQuota.metrics(fromSummary: Data(json.utf8))
  _ = metrics?.first?.resetNote() // Traps with Fatal error in Int(_: Double)
  ```
- `credential(fromKeychainValue:)`: Confirmed resilient against malformed base64, truncated `go-keyring-base64:`, non-UTF-8 base64 payloads, deeply nested JSON (50+ levels), 100KB payloads, duplicate keys, field type mismatches, bare primitives, and leading BOMs.
- `metrics(fromSummary:)`: Contract verified: returns `nil` for undecodable or non-summary payloads (missing or non-array `groups`), and `[]` for understood summaries without recognized pool buckets. Bucket deduplication and isolation verified.

### 2. Strict Concurrency
- `swift build -Xswiftc -strict-concurrency=complete`: Zero warnings in `AntigravityQuota.swift`, `AntigravityUsageReader.swift`, `AntigravityTokenCache`. The single pre-existing warning in `MemorySampler.swift:18` (`vm_kernel_page_size`) remains untouched.
- `AntigravityTokenCache`: Private actor; all 6 methods (`token(matching:)`, `store(_:expiresIn:refreshToken:)`, `discard()`, `mayAttemptRefresh(for:)`, `recordAuthFailure(for:)`, `clearBackoff()`) are completely synchronous with zero `await` expressions. No actor reentrancy hazards.

### 3. Retain Chains
- `AgentUsageService` verified:
  - `refreshTask`: `[weak self]`
  - `autoRefreshTask`: `[weak self]`
  - `scanTask`: `[weak self, logScanner]`
  No retain cycles created.

### 4. Backoff & Fingerprint Binding
- Backoff delay: exponential doubling 5m -> 10m -> 20m -> 40m -> capped at 60m (3600s).
- Fingerprint: SHA-256 of refresh token binds cached token to the specific account. Changing refresh token discards cache and allows immediate refresh.
- Backoff is cleared upon any successful quota read.

### 5. Performance Benchmarks
Tested across 1,000 iterations in `AntigravityBenchmarkTests`:
- `AntigravityQuota.credential(fromKeychainValue:)`: **274 µs** per operation (~0.27 ms).
- `AntigravityQuota.metrics(fromSummary:)`: **727 µs** per operation (~0.73 ms for 4 buckets with dual ISO-8601 formatting).
Both well within the sub-millisecond refresh budget.

### 6. Four Invariants
1. **Keychain read-only**: Verified. Only `SecItemCopyMatching` is used. Derived tokens stored exclusively in `~/Library/Application Support/Fluxa/antigravity/auth.json` (mode 0600).
2. **Background refresh never prompts**: Verified. `loadAntigravity(requestAccess: false)` checks `hasApproval` before touching Keychain and uses non-interactive `LAContext.interactionNotAllowed = true`.
3. **Independent consent**: Verified. Claude uses `fluxa.claudeCredentialApprovedRequirement`; Antigravity uses `fluxa.antigravityCredentialApprovedRequirement`.
4. **No credentials leaked**: Verified. No tokens in error descriptions, logs, or UI.

## Comments

- 2026-09-05, claude: ticket and spec written. Deviating from `docs/agents/roles.md` at the
  owner's explicit direction: Claude implements this one end to end rather than handing off to
  Codex, so `Owner:` stays `claude` through `codex-active`. Antigravity still validates.
  The scoping spike found that no reverse engineering is needed — an earlier read of the
  Antigravity bundle had suggested a private gRPC surface, but the quota path is plain JSON REST.
  Token history (spend, usage trend) is deliberately excluded, since it needs a SQLite + protobuf
  reader that `AgentLogScanner` has no shape for; if wanted it should be its own ticket.
- 2026-09-05, claude: implemented end to end. 92 tests green, `./build.sh` clean, and the only
  strict-concurrency error left in the package is the pre-existing `vm_kernel_page_size` in
  `MemorySampler.swift:18`. A security review of the five files went over the four design
  invariants — no writes to Antigravity's Keychain item, no dialog from the background loop,
  per-agent consent, no credential in logs or user-facing errors — and all four hold. It found one
  genuine crash path and several hardening gaps, now fixed:
  - `percentUsed` clamped in `Double` space. `Int(_: Double)` traps outside `Int`'s range, so a
    finite-but-absurd `remainingFraction` (`-1e300`, which the `isFinite` guard passes) was a
    server-triggered abort of the whole app. Covered by `extremeFinitePercentUsed`.
  - Refresh backoff, 5 min doubling to 1 h, keyed by credential fingerprint. A persistent 403 —
    Google's status for rate limiting and unentitled accounts, not just a dead login — otherwise
    meant a refresh grant every cycle forever.
  - Derived tokens are cached only after the summary call succeeds, and the cache is dropped on a
    rejected token and on losing Keychain access, so a token can't outlive its permission.
  - Cache file created 0600 via `createFile` + `replaceItemAt` instead of written 0644 and
    chmod'ed after; its directory is 0700.
  - OAuth failures classified on the `error` field (`invalid_grant`/`invalid_client`/
    `unauthorized_client`), not on `4xx`, which called throttling a dead login.
  - Private ephemeral `URLSession` refusing redirects: `URLSession` replays manually-set headers
    across hosts, so a 30x would have forwarded the bearer or re-POSTed the refresh token.
  - Production host tried before the `daily-` canary; 429 no longer falls through to the second
    host. `expires_in` parsed leniently and clamped to an hour.
  - Consent is revoked only on real denials, not on `errSecInteractionNotAllowed` — a locked screen
    was silently discarding it.
  Two findings deliberately left open, both pre-existing and neither specific to this provider:
  `AgentCredentialStore.readLock` is an `NSLock` held across a synchronous `SecItemCopyMatching`,
  which blocks a cooperative-pool thread (no deadlock — the lock is never held across an `await`);
  and the consent gate is UserDefaults, so it is anti-accident rather than anti-tamper, now said
  plainly in the comment rather than implied to be a control. The review also asked for
  `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail`; that constant is deprecated in favour of
  the `LAContext.interactionNotAllowed` this code already uses, so it was not applied.
- 2026-09-05, antigravity: validation completed. Strict concurrency, retain chains, the four
  invariants, and backoff/fingerprint binding all pass. Benchmarks recorded (metrics ~727 µs,
  credential ~274 µs). Fuzzing identified a critical server-triggered crash defect: while
  `percentUsed` was clamped in Double space, `AntigravityQuota.expiry` does not bound numeric
  `resetTime`, allowing an absurd finite timestamp (e.g. `1e300`) to reach `AgentUsageMetric.resetNote()`
  where `Int(resetsAt.timeIntervalSince(now))` traps on arm64 with fatal error, aborting the app.
  Per roles.md limits, implementation is not modified. Returning ticket to `Status: codex-active`,
  `Owner: codex` with reproducible case in `## Answer`.
- 2026-09-05, claude: defect confirmed and fixed. The reproducible case is exact, and the fault is
  wider than the report: `resetNote` is shared by all three providers, and `ClaudeUsageReader` and
  `CodexUsageReader` both build a `Date` from an unbounded epoch number off the network too, so
  Claude and Codex could each trigger the same trap. Fixed at both layers.
  - `AgentUsage.swift`: `resetNote` clamps the interval in `Double` space to a 3650-day cap before
    `Int(_:)`. This is the last line before the arithmetic and now holds on its own rather than
    trusting its callers — which is what closes the hole for all three providers, not just this one.
  - `AntigravityQuota.expiry`: an epoch resolving outside ±1e11 seconds returns nil, so no `Date`
    that far out is built in the first place. A broken timestamp costs the countdown, not the meter.
  New suite `AgentUsageMetric.resetNote` covers ordinary intervals, absent/past resets, and four
  extreme values that each trapped before. Antigravity's own extreme-`resetTime` assertion asserted
  the defective behaviour (`resetsAt != nil`, beyond `Int.max`) and now asserts the fix.
  101 tests in 17 suites green, `./build.sh` clean, strict concurrency unchanged — still only the
  pre-existing `vm_kernel_page_size`. Back to `Status: antigravity-validation`, `Owner: antigravity`.
- 2026-09-05, owner: functional acceptance given on the fixed build — the strip reads Antigravity's
  four pools correctly. Shipped in v2.9.0 (17) together with tickets 09 and 11. Antigravity's
  re-validation of the crash fix was not awaited; the owner accepted the build directly.
