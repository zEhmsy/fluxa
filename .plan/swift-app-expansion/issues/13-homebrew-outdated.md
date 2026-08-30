# 13 — Homebrew outdated packages

Status: spec-pending
Owner: claude
Type: task
Spec: —
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

Surface the count of outdated Homebrew packages, with the list in a submenu. Fits Fluxa's
developer-facing identity, next to agent usage and the GitHub profile.

`ShellRunner` exists; `brew outdated --json=v2` gives structured output.

Decide:

- **Refresh cadence.** `brew outdated` is slow and hits the network. It must not run on
  the popover-open path or every stats tick — cache with a long TTL and refresh in the
  background. Getting this wrong makes opening the menu feel broken.
- Locating the `brew` binary. It is `/opt/homebrew/bin/brew` on Apple Silicon,
  `/usr/local/bin/brew` on Intel, and neither is on `PATH` for an app launched by
  `launchd`. Never assume a login shell environment.
- What if Homebrew isn't installed: the feature must be absent, not an error.
  `QuickAction.Kind.unavailable(reason:)` already exists for this.
- Whether to offer `brew upgrade` from the menu, or only to report. **Recommend reporting
  only** — running an unattended upgrade from a menu bar app can break a working
  toolchain with no visible progress and no way to intervene.

## Notes

Scope this to reading. An upgrade action is a separate ticket with a separate risk
conversation.

## Answer

_(pending)_

## Comments

_(none)_
