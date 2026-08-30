# 12 — Settings backup and restore

Status: spec-pending
Owner: claude
Type: task
Spec: —
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

Export Fluxa's configuration to a file and import it back — for moving to a new Mac, or
recovering after a reset.

`AppSettings` is already `Codable`-shaped, so the mechanism is mostly there.

Decide:

- Format and file extension. JSON, human-readable, so a user can diff it.
- **A schema version field in the file.** Without one, a backup taken today is
  unrestorable after the next settings change, and this feature exists precisely to be
  used months later. This is the decision that makes or breaks the ticket.
- Import behaviour on an unknown or newer version: refuse clearly, never partially apply.
- What is excluded. **Anything from `AgentCredentials` must not be exported** — check
  what it holds before designing. Credentials in a plaintext JSON the user emails to
  themselves is how a convenience feature becomes a security incident.

## Notes

Restore replaces the user's current configuration. Confirm before applying, and state
what will be overwritten.

## Answer

_(pending)_

## Comments

_(none)_
