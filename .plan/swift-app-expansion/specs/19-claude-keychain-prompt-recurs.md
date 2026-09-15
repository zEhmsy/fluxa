# Spec 19 — Read Claude's credential through `/usr/bin/security`

Ticket: `issues/19-claude-keychain-prompt-recurs.md`
Author: claude, 2026-09-15

Make the Claude keychain grant a once-only act by reading the item through the Apple-signed tool
that wrote it, instead of through `SecItemCopyMatching` from an app macOS has no lasting way to
trust.

Everything marked *verified* was measured on this machine on 2026-09-15 and is restated in the
ticket's `## Provenance`. Do not re-derive it; do re-run the control test in D9.

## D1 — The one behavioural change

`AgentCredentialStore.loadClaude(requestAccess:)` keeps its signature, its file-first order and its
error vocabulary. Only the keychain step underneath changes: today `SecItemCopyMatching` with an
`LAContext`, after this ticket a bounded `/usr/bin/security` invocation.

Nothing else moves. Codex still reads `~/.codex/auth.json`, Antigravity still reads nothing at all,
and no code path anywhere gains the ability to write to the keychain.

## D2 — The invocation

*Verified: both argument shapes returned exit 0 silently on this Mac.*

Absolute path `/usr/bin/security`, never a `PATH` lookup — the whole security property here is that
the binary is the Apple-signed one, so it must not be resolvable to anything else.

Arguments, first shape:

```
find-generic-password -s "Claude Code-credentials" -a <NSUserName()> -w
```

On exit 44 from that shape, retry once without `-a`. Claude Code has used both item shapes, and the
existing code already tries both; keep that, in the same order.

Environment: pass only `HOME` (from `NSHomeDirectory()`). Do not inherit the process environment —
`DYLD_*` and `PATH` from whatever launched Fluxa have no business influencing this call.

Exit codes:

| Exit | Meaning | Result |
| ---- | ------- | ------ |
| 0 | item read | parse stdout, D4 |
| 44 | no such item | `nil` — absent, *not* denied. Never revokes the in-app approval |
| other, or timeout | refused, or a dialog nobody answered | `AccessError.notAllowed`, revokes the approval as today |

`stderr` is drained and discarded. It is diagnostic text only, and it must not reach a log or an
error message shown to the user — `security` is free to change its wording, and the user can do
nothing with it.

## D3 — A dialog must never block the refresh loop

*This is the requirement most likely to be skipped, and the most important one in the spec.*

On a Mac whose item ACL does not list `security` — a credential written by some other Claude Code
build, a restored keychain — the tool will raise the dialog itself and block until someone answers.
Fluxa's refresh runs from a background loop every few minutes. A call that can block forever on that
path is exactly the defect that kept the menu-bar item from ever appearing in ticket 18, and it is
not to be reintroduced one ticket later.

Therefore: wait at most **5 seconds** for exit. On expiry, `terminate()`, and if the process is
still alive a moment later, `kill`. Treat it as the "other" row of D2's table. Reap the process in
every path, including the timeout path, so a stuck `security` is never left behind.

Five seconds is chosen against a measured baseline of an immediate return; it is long enough that a
loaded Mac does not produce false timeouts, and short enough that a user who is looking at the
popover sees an error rather than a spinner that never resolves.

## D4 — The secret's handling

The blob contains a live access token *and* a long-lived refresh token. While it is in the process:

- Read `stdout` as `Data` through a `Pipe`, and read the pipe **to end before** `waitUntilExit()`.
  Waiting first deadlocks whenever the child's output exceeds the pipe buffer, and the size of this
  blob is not Fluxa's to guarantee.
- Parse JSON from that `Data` directly. Never construct a `String` of the whole blob, never
  interpolate it, never write it to a file, never put it in an `Error`, and never log it at any
  level.
- `security -w` prints a hex string prefixed `0x` when the value is not valid UTF-8. That is not a
  credential Fluxa can use: treat a payload that does not parse as JSON as
  `AccessError.unreadable`, the existing case, rather than attempting to decode hex.
- Trailing newline from the tool is stripped before parsing.

Swift cannot reliably zero a `String`, so the honest boundary is: keep the blob as `Data`, keep only
the derived `accessToken` beyond the parse, and let `Data`'s buffer go out of scope promptly. Say so
in a comment rather than implying an erasure the language does not provide.

## D5 — The `SecItemCopyMatching` path is removed, not kept as a fallback

Deleting it takes `import LocalAuthentication`, the `LAContext`, `kSecUseAuthenticationContext` and
`deniedStatuses` with it.

A fallback is tempting and wrong: it would restore the dialog on exactly the machines where the
new path failed, which is the behaviour this ticket exists to end, and it would make the app's
behaviour depend on which of two mechanisms happened to answer. One path, one set of outcomes.

## D6 — Consent after the dialog is gone

Keep `hasApproval`/`recordApproval` and their binding to the current code-signing requirement
exactly as they are. The first read for a given signature still has to come from the
**Connect Claude** button in Permissions & First Run; background refreshes still refuse to initiate
first access.

What changes is the honesty of the comment around it. The current code says the Keychain ACL
"remains the boundary that actually protects the credential". For *this* item that was never true:
its ACL lists `security`, so any process running as this user can read it with one command. Correct
that comment, and say plainly that the in-app opt-in is now the consent point, not a convenience
in front of a system gate.

The same correction is owed to `README.md`'s permissions table, whose **Keychain** row tells the
user to "choose *Always Allow* only if you trust this copy" — advice about a dialog they will no
longer see. Update the row to describe the in-app opt-in. Do not touch the rest of the README.

## D7 — Shape for testability

`AgentCredentials.swift` lives in the app target, which has no tests. Put the two testable pieces in
`FluxaCore`:

1. `SecurityToolKeychain` — owns D2's argument shapes and D2's exit-code table, and takes its
   process runner as an injected closure:

   ```swift
   public typealias KeychainCommandRunner =
       @Sendable ([String]) throws -> (status: Int32, standardOutput: Data)
   ```

   The real runner (`Process`, D3's timeout, D4's pipe discipline) stays in the app target, because
   it is the part that talks to the system. The type is `Sendable`; the reader is called from the
   usage refresh, which is not on the main actor.

2. `ClaudeCredentialBlob` — a pure parse of the JSON `Data` into `accessToken`, `expiresAt`,
   `subscriptionType`, `scopes`. `AgentCredentialStore` keeps `ClaudeCredentials` and its
   `isExpired` / `canReadUsage` derivations, mapping from the blob.

`AgentCredentialStore.loadClaude` stays the app-side composition of the two, with its `readLock`,
its approval handling and its file-first order unchanged.

## D8 — Out of scope

No credential is ever written, exported, refreshed or copied to disk. No change to Codex or
Antigravity. No version bump, no `Info.plist` edit, no packaging, no appcast, no release notes, no
commit to `main` beyond the ticket's own code and tests — the owner and Claude handle the release
after verification.

## D9 — Acceptance

Automated, all required before handoff:

- `swift test` green, with new `FluxaCoreTests` covering, at minimum: a well-formed blob; exit 44 →
  `nil`; a non-zero exit → throw; `0x…` hex output → `unreadable`; truncated JSON → `unreadable`; a
  blob whose `scopes` lack `user:profile` → `canReadUsage == false`; and the second argument shape
  being tried only after a 44 from the first.
- `swift build -c release -Xswiftc -warnings-as-errors`.
- `swift build -Xswiftc -strict-concurrency=complete` with no new warning from the touched files.

Manual, on the owner's Mac:

- With no approval recorded, the strip reports the "enable credential access" message and raises no
  dialog from the background loop.
- **Connect Claude** in Permissions & First Run returns numbers with **no macOS dialog at all**.
- Quit and relaunch: numbers return with no dialog and no button press.
- Re-run the control test from the ticket and record the exit code observed:
  `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w >/dev/null; echo $?`
- Confirm by inspection that no code path passes the blob to a logger, an error, or a file.

The ticket's real proof — the grant surviving a Claude Code token refresh — takes about eight hours
of wall clock and belongs to the owner, not to validation. Note it as pending in `## Answer` rather
than claiming it.
