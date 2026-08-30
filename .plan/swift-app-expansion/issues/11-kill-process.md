# 11 — Process killer

Status: spec-pending
Owner: claude
Type: task
Spec: —
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

A submenu listing running processes so the user can force-quit one without opening
Activity Monitor. `QuickAction.Kind.menu`, like `audioOutput` already is.

Decide:

- **What to list.** Every process is hundreds of rows, most of them system daemons the
  user must not kill. Default to user-owned GUI applications
  (`NSWorkspace.runningApplications`, `.regular` activation policy) — short, safe, and
  covers the actual use case of a hung app.
- Sort order: CPU usage descending is the useful one, and Fluxa already samples CPU.
- `SIGTERM` first, `SIGKILL` only if it doesn't exit. Terminating with `SIGKILL` outright
  loses unsaved work.
- Confirmation before killing. This is destructive and mis-clickable from a menu.

## Notes

Never offer to kill processes owned by root or by another user — it will fail without
privileges, and offering an action that can't work is worse than omitting it.

`ShellRunner` exists, but `NSRunningApplication.terminate()` / `forceTerminate()` is the
better route for GUI apps: it gives the app a chance to save.

## Answer

_(pending)_

## Comments

_(none)_
