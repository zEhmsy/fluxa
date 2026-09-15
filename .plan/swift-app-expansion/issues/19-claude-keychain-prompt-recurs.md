# 19 — The Claude Keychain grant never sticks

Status: codex-active
Owner: antigravity
Type: bug
Spec: specs/19-claude-keychain-prompt-recurs.md
Blocked by: —
Source: Owner request, 2026-09-15 — *"vedi se c'è un modo per riuscire a concedere una volta i
permessi per leggere i token di claude e non doverlo fare sempre, che non riguardi il firmare l'app
con un developer ID"*. Diagnosis is Fluxa's own; no third-party source was read. See `## Provenance`.

## Question

Fluxa reads Claude's quota from the OAuth blob Claude Code stores in the login keychain
(`Claude Code-credentials`). Choosing **Always Allow** in the macOS dialog is supposed to grant that
once. It does not: the dialog returns, repeatedly, and the owner has had to re-grant it for months.

Signing the app with a Developer ID is excluded by the owner. The question is whether the grant can
be made to stick without one.

## Provenance

Established on this machine on 2026-09-15:

- The item's `cdat` is 2026-03-20 and its `mdat` was that morning: Claude Code **updates the same
  item** on every token refresh rather than replacing it. The refresh is what discards the ACL entry
  that "Always Allow" wrote, which is why the grant is always gone by the next refresh (~8 h).
- The item carries the `apple-tool:` partition, the tag `/usr/bin/security` writes. macOS serves
  such an item silently to an Apple-signed process, or to one whose Team ID is in the partition
  list. A self-signed app has no Team ID, so there is nowhere for a lasting grant to be recorded —
  the stable `Fluxa Code Signing` certificate fixed the *designated requirement* churn and could not
  touch this.
- **Control test.** `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`
  returned exit 0 with no dialog and no delay, from this session, on this Mac. A missing item exits
  44. That is the whole finding: the tool that writes the item is in its own ACL, and reading
  through it is silent and survives every refresh.

Public reports of the same two causes, read as descriptions of macOS behaviour only — no
third-party source code was read for this ticket:

- <https://github.com/anthropics/claude-code/issues/22144> — upstream request for a usage cache so
  third-party tools need not touch the keychain at all
- <https://github.com/anthropics/claude-code/issues/81707> — partition-list / Team ID mismatch
- <https://github.com/steipete/CodexBar/issues/485>, `#624`, `#2115` — the recurring dialog
- <https://www.silverfort.com/blog/skipping-the-lock-a-claude-code-cli-weakness-lets-any-macos-process-read-stored-credentials/>
  — the ACL on this item lists only `security`, so any user-mode process can already read it

## Decide

- **Where consent lives once the dialog is gone.** The macOS dialog looked like the boundary and
  was not one: the credential is readable by any process running as this user. The in-app opt-in
  becomes the consent point, explicitly rather than incidentally. See D6.
- **What happens on a Mac where the dialog still appears.** It must never block the refresh loop —
  that is the failure mode that cost the menu-bar item in ticket 18. See D3.
- **Whether to keep the `SecItemCopyMatching` path as a fallback.** Spec says no; one path, see D5.

## Rejected alternatives

- **Exporting to `~/.claude/.credentials.json`.** Fluxa already prefers that file when it exists, so
  this would work — until the next refresh, after which the file holds a dead token while the
  keychain holds the live one. It also puts a long-lived refresh token in plaintext on disk. Worse
  than the problem.
- **`security set-generic-password-partition-list`.** Confirms the diagnosis; does not survive the
  next refresh, for the same reason "Always Allow" does not.
- **Waiting for the upstream usage cache.** Nothing to implement, no date.

## Comments

- 2026-09-15, claude: diagnosed and specced. Assigned to Antigravity for implementation at the
  owner's explicit direction, as on tickets 16 and 17; the standing role division in
  `docs/agents/roles.md` is unchanged by it. Claude verifies the result before any release.
