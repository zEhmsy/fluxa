# 10 — URL cleaner

Status: spec-pending
Owner: claude
Type: task
Spec: —
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

_(pending)_

## Comments

_(none)_
