# 10 — URL cleaner

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/10-url-cleaner.md
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

One-shot action: take the URL on the clipboard, strip tracking parameters, put it back.

Smallest ticket in the set and a good one to run the Claude → Codex → Antigravity loop on
end to end.

Decide:

- **The parameter list.** `utm_*`, `fbclid`, `gclid`, `igshid`, `mc_eid`, `_hsenc`,
  `si` on youtu.be, `ref_src`/`ref_url` on x.com. Prefix rules plus exact matches.
- **Host-specific rules.** Amazon URLs shrink to `/dp/<ASIN>`; YouTube `t=` must be kept
  while `si=` goes. Generic stripping alone leaves most of the noise.
- **What happens on a non-URL clipboard.** Do nothing and say so, rather than mangling text.
- Whether to preserve the original for one undo step.

## Notes

The failure that matters is **breaking a working link**. Some `?id=` parameters are
load-bearing. When in doubt, keep the parameter — a slightly dirty URL that works beats a
clean one that 404s. Antigravity should fuzz this with real URLs, including ones where
the tracking parameter is the only parameter.

## Answer

Validated 2026-08-30 by Antigravity:

1. **Test Suite & Fuzzing (`FluxaCoreTests.URLCleanerTests`)**:
   - `swift test` runs **15 test cases in `URLCleanerTests`** (18 tests total across 2 suites), **0 failures**:
     - Generic tracking parameter isolation and combinations (`utm_*`, `fbclid`, `gclid`, `igshid`, `mc_*`, `_hs*`, `ref_*`).
     - Exact match / case-sensitivity (`UTM_SOURCE` and `not_utm_x` kept untouched).
     - YouTube: `si` stripped; playback time `t` and playlist `list` strictly preserved across `youtube.com`, `youtu.be`, `music.youtube.com`.
     - X/Twitter: `s`, `t`, `ref_src`, `ref_url` stripped on `x.com` and `twitter.com`; `t` preserved everywhere else.
     - Amazon: Canonicalization of `/dp/<ASIN>` and `/gp/product/<ASIN>` to `https://<host>/dp/<ASIN>` across international stores (`amazon.com`, `amazon.de`, `amazon.it`, `amazon.co.jp`, `amazon.fr`, etc.); non-product paths receive generic pass only.
     - Edge Cases & Boundary Fuzzing: URL fragments (`#hash`), explicit ports (`:8443`), percent-encoded queries (`%20`), duplicate parameters, empty query values (`utm_source=`), single-parameter stripping leaving no trailing `?`.
     - Non-URL & Malformed Inputs: Empty strings, plain text, relative paths, schemes without host (`file:///`, `data:`), malformed URLs — all safely return `nil` without mutating pasteboard.
2. **Performance Benchmarks**:
   - 50,000 URL clean operations across diverse real-world URLs (YouTube, Amazon ASIN, X, long multi-tracker marketing URLs, already-clean URLs) executed in **0.133s** (~**2.66 µs** / operation).
3. **Strict Concurrency**:
   - `swift build -Xswiftc -strict-concurrency=complete` produced **0 new warnings** across `Sources/FluxaCore/Services/URLCleaner.swift` and `Sources/Fluxa/Services/URLCleanerService.swift`.
4. **Retain Cycles & Memory Audit**:
   - `URLCleaner` is a stateless pure enum.
   - `URLCleanerService` is `@MainActor final class` holding no long-lived closures or retaining references.
5. **Build & Code Signing**:
   - `./build.sh` passed cleanly with `-warnings-as-errors`, creating signed `Fluxa.app` bundle.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-30, claude — Spec written. Pure cleaning logic (`URLCleaner`) goes in
  `FluxaCore` as `package`, clipboard I/O (`URLCleanerService`) stays `@MainActor` in
  `Sources/Fluxa`, following the split ticket 02 established. Generic tracking-param list
  plus host rules for YouTube/Amazon/X, with an explicit safety rule: unlisted params are
  never touched. Wiring follows the existing `screenClean` momentaryButton pattern in
  `PopoverViewModel` (lines 260-263) and `QuickAction.swift`.
- 2026-08-30, codex — Implemented D1–D5 and handed off to Antigravity. Files touched:
  `Sources/FluxaCore/Services/URLCleaner.swift`,
  `Sources/Fluxa/Services/URLCleanerService.swift`,
  `Sources/Fluxa/Models/QuickAction.swift`,
  `Sources/Fluxa/ViewModels/PopoverViewModel.swift`,
  `Sources/Fluxa/Views/ControlDeckTheme.swift`,
  `Tests/FluxaCoreTests/URLCleanerTests.swift`, and this ticket.

  `URLCleaner` is `package`-visible, imports Foundation only, applies the exact generic and
  host-specific rules, and rejects relative/non-host URLs. `URLCleanerService` is `@MainActor`;
  its `clearContents()` and `setString` calls are reachable only after a string parses to an
  absolute hosted URL and produces an actual cleaned result. The test suite includes a relative
  non-URL containing `utm_source`, proving it still returns `nil`; combined with the service guard,
  that proves non-URL clipboard text cannot reach a pasteboard mutation. No live pasteboard test or
  user clipboard mutation was performed. The pre-existing `FocusOnboardingView` copy button remains
  the unrelated pasteboard use cited by the spec; the URL-cleaner flow touches `NSPasteboard` only in
  `URLCleanerService`.

  `swift test` passed with 14 tests in 2 suites (11 URL-cleaner tests plus the existing 3).
  `./build.sh` passed cleanly with warnings-as-errors and recreated the ignored local Fluxa 2.6.2
  (13) arm64 bundle without installation, launch, key access or publication.

  The only file the spec did not list was `ControlDeckTheme.swift`: adding an `ActionID` makes its
  action-color switch non-exhaustive, so `.urlCleaner` received the existing `brandBlue` token.
  `AppSettings` already appends new `ActionID` cases to saved action order, so no migration change was
  needed. No lightweight toast/flash channel exists in `PopoverViewModel`; per D5, a no-op remains
  silent rather than introducing a new feedback pattern. No other spec gap or D1–D5 deviation arose.
- 2026-08-30, antigravity — Validation complete. Extended test suite with edge-case fuzzing (fragments, ports, percent-encoding, international Amazon domains, duplicate parameters, non-hosted URLs) and performance benchmark (~2.66 µs/operation). Verified `swift test` (18/18 passed), `swift build`, `./build.sh` (passed with `-warnings-as-errors`), and strict concurrency check (0 new warnings). Status advanced to `ready-for-handoff`.

