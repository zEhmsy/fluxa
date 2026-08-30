# Spec 10 — URL cleaner

Ticket: `issues/10-url-cleaner.md`
Author: claude
Date: 2026-08-30

## Goal

A one-shot quick action: take whatever URL is on the clipboard, strip tracking
parameters, put the cleaned URL back. Fits the existing `QuickAction.Kind.momentaryButton`
pattern already used by `ScreenClean` and others.

## Where this lives

**Pure logic goes in `FluxaCore`, not `Sources/Fluxa`.** The actual cleaning — parsing a
URL, deciding which query items to drop — has no AppKit/SwiftUI dependency and is exactly
the kind of code ticket `02` extracted `FluxaCore` to hold. Only the clipboard I/O touches
`AppKit` (`NSPasteboard`) and belongs in the app target.

```
Sources/FluxaCore/Services/URLCleaner.swift      — pure: URL in, URL out (or nil)
Sources/Fluxa/Services/URLCleanerService.swift    — NSPasteboard read/write, calls URLCleaner
Tests/FluxaCoreTests/URLCleanerTests.swift        — the fuzzing surface Antigravity extends
```

This split means Antigravity can test the actual cleaning logic with `@testable import
FluxaCore` and zero UI dependency — no popover, no pasteboard mock needed for the rules
themselves.

## D1 — The cleaning function's shape

```swift
package enum URLCleaner {
    /// Returns a cleaned URL, or nil if `url` needed no changes.
    /// Never throws: an unparseable or already-clean URL round-trips to nil, not an error.
    package static func cleaned(_ url: URL) -> URL?
}
```

Returning `nil` for "no change" (rather than echoing the input back) lets the caller
distinguish "I cleaned it" from "there was nothing to do" without a separate flag — the
caller needs that distinction to skip the pasteboard write when nothing changed.

## D2 — Stripping rules

Two layers, generic first, host-specific second — because generic alone is not enough
(see D3 for why).

**Generic — strip these query parameter names wherever they appear:**

```
utm_source, utm_medium, utm_campaign, utm_term, utm_content, utm_id
fbclid, gclid, gclsrc, dclid, msclkid
igshid, mc_eid, mc_cid
_hsenc, _hsmi
ref_src, ref_url
```

Match by exact parameter name, case-sensitive. Do not pattern-match on prefix beyond the
literal `utm_` family listed above — a broader prefix rule risks stripping a legitimate
`utm_` parameter some site defines for its own routing.

**Host-specific — layered on top of the generic pass:**

| Host | Rule |
|---|---|
| `youtube.com`, `youtu.be`, `music.youtube.com` | Strip `si`. **Keep `t` and `list`** — they are playback position and playlist, not tracking. |
| `amazon.*` (any TLD) | If the path contains `/dp/<ASIN>` or `/gp/product/<ASIN>`, rewrite to `https://<host>/dp/<ASIN>` — drop every query parameter. Otherwise fall through to the generic pass only; do not guess at an ASIN from a non-standard path. |
| `x.com`, `twitter.com` | Strip `ref_src`, `ref_url`, `s`, `t` (X's own share-tracking params, distinct from YouTube's `t`). |

Host matching is case-insensitive and must handle a leading `www.`.

## D3 — Safety rule: never break a working link

This is the one failure that matters more than leaving noise behind. **When in doubt,
keep the parameter.** Concretely:

- A parameter not in the generic list and not covered by a host rule is left alone,
  full stop. Do not attempt a heuristic ("looks like tracking") beyond the explicit lists.
- If stripping would leave a parameter list empty, drop the `?` entirely rather than
  leaving `url?`.
- If stripping would remove the *only* parameter and that parameter turns out to be
  load-bearing for a host not in the table, this spec accepts that risk for the generic
  list only — the generic names above are widely-recognized tracking parameters with no
  legitimate routing use. The host-specific table exists precisely to encode the
  exceptions where a same-named parameter is *not* tracking (YouTube's `t` and `list`).
- Malformed input (not a valid URL) → `cleaned` returns `nil`. Never crash, never mutate
  something that doesn't parse.

## D4 — Clipboard behaviour (`Sources/Fluxa/Services/URLCleanerService.swift`)

```swift
@MainActor
final class URLCleanerService {
    /// Reads the pasteboard, cleans if possible, writes back if changed.
    /// Returns whether a write happened, so the caller can give feedback.
    func cleanClipboard() -> Bool
}
```

- Read `NSPasteboard.general.string(forType: .string)`. If it isn't present, or
  `URL(string:)` fails to parse it, do nothing and return `false`. **Do not mutate the
  clipboard when the content isn't a URL** — a user who copies a sentence and hits the
  action by mistake must get their sentence back untouched, not an error and not a mangled
  string.
- If `URLCleaner.cleaned` returns `nil` (already clean, or one of the "leave alone" cases),
  do not touch the pasteboard. Writing back an identical string is a no-op that still
  clears pasteboard history in some clipboard managers — avoid it.
- On an actual change: `clearContents()` then `setString(_:forType: .string)`, following
  the existing pattern in `FocusOnboardingView.swift:243-244`.
- No undo mechanism. The ticket floated preserving one prior value for undo; skip it for
  this iteration — it needs a place to live (a stack? one slot?) that doesn't exist
  anywhere in Fluxa yet, and is a separate ticket if wanted later.

## D5 — Wiring into `QuickAction`

Add to `ActionID` in `Sources/Fluxa/Models/QuickAction.swift`:

```swift
case urlCleaner // Strips tracking parameters from the clipboard's URL
```

Add an entry to `ActionCatalog.all` with `controlStyle: .momentaryButton(label: "Clean")`,
following the existing entries' shape (icon, tint, subtitle) — match the file's established
style rather than inventing a new one.

Wire it in `PopoverViewModel` the same way `screenClean` is wired at line 260-263: a
`case .urlCleaner:` branch calling `urlCleanerService.cleanClipboard()`.

**Feedback on failure** (nothing to clean, or clipboard wasn't a URL): the row is a
momentary button with no persistent state, so there's no toggle to reflect success/failure
in. Check whether `PopoverViewModel` has an existing lightweight feedback channel (a toast,
a brief icon flash) for other momentary actions before inventing one. If none exists, doing
nothing visible on a no-op is acceptable — silently declining to mutate a non-URL clipboard
is the correct behavior in D4, not a failure to announce.

## Tests (`Tests/FluxaCoreTests/URLCleanerTests.swift`)

This is the ticket's real fuzzing surface, and belongs to Antigravity to extend — these are
the minimum before handoff:

- Each generic parameter name strips in isolation and combined with 2+ others.
- A parameter that merely *contains* `utm_` as a substring but isn't in the exact list
  (e.g. `not_utm_x`) is preserved — proves exact-match, not substring-match.
- YouTube: `si` stripped, `t` and `list` preserved, on both `youtube.com` and `youtu.be`.
- X/Twitter: `t` stripped (X's own), distinct from YouTube's `t` being preserved — these
  must not collide in the implementation via a single global "strip t" rule.
- Amazon: `/dp/<ASIN>?...` collapses to `/dp/<ASIN>` with all params dropped; a
  non-`/dp/`-shaped Amazon URL only gets the generic pass.
- A URL with zero tracking parameters returns `nil`.
- A URL whose only parameter is a tracking one collapses to no trailing `?`.
- Malformed strings, empty string, and a non-URL sentence all return `nil` without
  crashing.
- `www.` prefix is host-matched the same as bare host.

## Acceptance

1. `URLCleaner.cleaned` lives in `FluxaCore`, `package`-visible, zero AppKit import.
2. `URLCleanerService` in `Sources/Fluxa`, `@MainActor`, only place touching `NSPasteboard`.
3. New `ActionID.urlCleaner` case wired end-to-end: appears in the popover, cleans on tap.
4. `swift test` passes including the new suite.
5. `./build.sh` passes (`-warnings-as-errors`).
6. Clipboard containing non-URL text is provably untouched after the action runs.

## Out of scope

Undo. A settings toggle for which rules apply. Any parameter list beyond D2 — new hosts or
parameters are a follow-up ticket, not scope creep here.
