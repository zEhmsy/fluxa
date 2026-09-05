# Spec 09 — Color picker

Ticket: `issues/09-color-picker.md`
Author: claude
Date: 2026-08-31

## Goal

A one-shot quick action: the cursor becomes a picker, the user clicks a pixel anywhere on
screen, the hex code lands on the clipboard. Fits the existing `QuickAction.Kind.momentaryButton`
pattern already used by `ScreenClean` and `URLCleaner`.

## The whole interaction is `NSColorSampler`

Per the ticket's own note: `NSColorSampler` (AppKit, macOS 10.15+) gives the cursor-becomes-
a-picker interaction, the magnified loupe, and the pixel sample — for free, and it needs no
Screen Recording permission. A hand-rolled version using `CGWindowListCreateImage` does need
that permission (with recurring prompts as of macOS 15) and would spend real effort
reproducing a system control pixel-for-pixel. **Do not build a custom picker.** This closes
the ticket's "loupe" question: yes, because it's free, not because it was requested.

## Where this lives

Same split as ticket 10 (`URLCleaner`): the part that needs AppKit stays in the app target,
the pure transformation goes in `FluxaCore` so Antigravity gets a fuzzable, AppKit-free
surface.

```
Sources/FluxaCore/Services/ColorFormatting.swift   — pure: RGB components in, hex string out
Sources/Fluxa/Services/ColorPickerService.swift     — NSColorSampler + NSPasteboard, calls ColorFormatting
Tests/FluxaCoreTests/ColorFormattingTests.swift     — rounding/clamping fuzzing surface
```

`NSColorSampler` and `NSColor` themselves stay out of `FluxaCore` — the package has zero
AppKit imports today (verified: `grep -rl "import AppKit" Sources/FluxaCore/` is empty) and
this ticket doesn't need to break that.

## D1 — Format: hex only, no setting

Ticket asks to decide format and whether to make it configurable "only if it's free."
Decision: **hex `#RRGGBB`, uppercase, no alpha, and no setting.**

- `rgb()` or an `NSColor` literal are not free to add: there is no existing per-action
  settings surface to hang a picker on. `TrackpadScaleUnit` (ticket 06 era) is the closest
  precedent for a small enum preference, but it lives inside that feature's own dedicated
  window (`TrackpadScaleWindowView`) — color picker has no window, it's a single tap. Adding
  a new home for one enum toggle (a Customize section, a per-row menu) is exactly the kind
  of scope this ticket's own "only if it's free" test is meant to block.
- Hex is the format every color tool defaults to (browser inspectors, design tools, Xcode's
  own color panel) and pastes usefully into CSS, Swift `Color(hex:)` helpers, and design
  files without transformation. It's the correct single default.
- No alpha component: a sampled screen pixel is opaque display output, not a color with
  meaningful transparency. `#RRGGBB`, not `#RRGGBBAA`.

## D2 — Colour space: convert to sRGB

A screen pixel comes off `NSColorSampler` in the display's own color profile, not
necessarily sRGB. Decision: **always convert to sRGB before reading components.**

- sRGB is what every hex code a user will paste that value into (CSS, HTML, most design
  tools) assumes. Handing back a P3 or display-profile hex would silently shift the color
  when pasted elsewhere — exactly the kind of surprising, hard-to-notice bug this project's
  clean-room rules exist to avoid.
- Conversion: `sampledColor.usingColorSpace(.sRGB)`. If it returns `nil` (color has no valid
  conversion path — rare, but `usingColorSpace` is documented as optional-returning), decline
  the whole action rather than reading raw components off a color space that may not even be
  RGB-shaped. Reading `.redComponent` on a non-RGB `NSColor` logs an AppKit assertion and
  returns garbage; failing silently and cleanly is the safer failure mode than that.

## D3 — `ColorFormatting` (`Sources/FluxaCore/Services/ColorFormatting.swift`)

```swift
package enum ColorFormatting {
    /// Formats sRGB components (each expected in 0...1) as uppercase "#RRGGBB".
    /// Values outside 0...1 are clamped, not rejected — a color space conversion can
    /// return components a hair outside range from floating-point rounding.
    package static func hex(red: Double, green: Double, blue: Double) -> String
}
```

- Clamp each component to `0...1`, multiply by 255, round to nearest integer
  (`(component * 255).rounded()`), clamp to `0...255`, format as two uppercase hex digits.
- Round, don't truncate — truncation systematically biases every channel down by up to
  1/255, which is visible on flat mid-tones.
- Pure function, `package`-visible, zero AppKit import. This is the whole fuzzing surface:
  boundary values (0.0, 1.0, values that round exactly at `.5`), out-of-range inputs
  (negative, > 1), and a handful of known colors (pure red/green/blue/white/black) with
  their expected hex strings.

## D4 — `ColorPickerService` (`Sources/Fluxa/Services/ColorPickerService.swift`)

```swift
@MainActor
final class ColorPickerService {
    /// Shows the system color sampler. Returns whether a hex value was copied —
    /// false covers both user cancellation (Esc) and a failed color-space conversion.
    func pickColor() async -> Bool
}
```

- Wrap `NSColorSampler`'s callback-based `show(selectionHandler:)` in
  `withCheckedContinuation` to fit the existing `async` `triggerAction` flow other momentary
  actions already use.
- `selectionHandler` receiving `nil` means the user pressed Esc or clicked outside a
  sampleable area — decline silently, same as D2's conversion-failure path. This is normal
  use, not an error; there is nothing to surface.
- On a non-nil color: convert per D2, extract `redComponent`/`greenComponent`/`blueComponent`
  from the converted color, pass to `ColorFormatting.hex`, write to `NSPasteboard.general`
  with `clearContents()` then `setString(_:forType: .string)` — the same two-call pattern
  `URLCleanerService` and `FocusOnboardingView.swift:243-244` already use.
- No Screen Recording, Accessibility, or any other permission request — `NSColorSampler`
  needs none. `PermissionsService` is untouched by this ticket.

## D5 — Wiring into `QuickAction`

Add to `ActionID` in `Sources/Fluxa/Models/QuickAction.swift`:

```swift
case colorPicker // NSColorSampler pixel picker → hex to clipboard
```

Add to `ActionCatalog.all`, matching the file's established shape:

```swift
QuickAction(
    id: .colorPicker,
    title: "Color Picker",
    subtitle: "Sample a pixel, copy its hex code",
    icon: "eyedropper",
    activeIcon: nil,
    tint: FluxaTheme.mint,
    controlStyle: .momentaryButton(label: "Pick")
)
```

`FluxaTheme.mint` is reused (already used once by `desktopIcons`, a toggle) rather than
adding a new palette color — every existing momentary action (`screenSaver` = purple,
`screenClean` = cyan, `urlCleaner` = blue, `lidAngle` = green, `trackpadScale` = amber)
already reuses colors shared with toggles; mint is the one palette entry no momentary
action currently uses, keeping the momentary-action row of icons visually distinct from
each other.

Wire in `PopoverViewModel.triggerAction`, following the `screenClean` shape at
lines 260–263 (close the popover first — the user needs the full screen, not a panel
sitting on top of it — then let the sampler take over):

```swift
case .colorPicker:
    closePopover?()
    try await Task.sleep(for: .milliseconds(200))
    _ = await colorPickerService.pickColor()
```

The `200ms` sleep matches `screenSaver`/`screenClean`'s existing delay for the popover's
close animation to finish before the next visual takes over — reuse the constant, don't
invent a second one.

**`ControlDeckTheme.actionColor(for:)` is an exhaustive switch over `ActionID`** — adding
`.colorPicker` to the enum without a case there is a compile error, not an oversight to
catch later. Add:

```swift
case .colorPicker: return isDark ? Self.rgb(84, 218, 166) : Self.rgb(19, 117, 83)
```

(`FluxaTheme.mint`'s own light/dark values, matching how every other case in that switch
inlines its tint rather than referencing `FluxaTheme` from a `Color`-returning context that
doesn't have `isDark` scoped the same way.)

**Feedback on failure**: same reasoning as `URLCleaner` D5 — a momentary button has no
toggle state to reflect success/failure in, and declining silently on cancel (Esc) is
correct, expected behavior, not a failure to announce. No new toast/flash mechanism is
introduced by this ticket.

## Tests (`Tests/FluxaCoreTests/ColorFormattingTests.swift`)

- Pure red/green/blue/white/black round-trip to their exact expected hex strings.
- A component that rounds up at the `.5` boundary (e.g. `254.5/255` → `FF`, not `FE`).
- Components at exactly `0.0` and `1.0`.
- Out-of-range components (`-0.1`, `1.1`) clamp instead of producing invalid hex digits or
  crashing.
- Output is always exactly 7 characters (`#` + 6 uppercase hex digits), never lowercase,
  never `#RGB` shorthand.

## Acceptance

1. `ColorFormatting.hex` lives in `FluxaCore`, `package`-visible, zero AppKit import.
2. `ColorPickerService` in `Sources/Fluxa`, `@MainActor`, the only place touching
   `NSColorSampler`/`NSPasteboard` for this feature.
3. New `ActionID.colorPicker` case wired end-to-end: appears in the popover, closes it,
   invokes the system sampler, and a click on a real pixel copies that pixel's `#RRGGBB` to
   the clipboard.
4. Pressing Esc during sampling leaves the clipboard untouched and produces no error.
5. `ControlDeckTheme.actionColor(for:)` has a `.colorPicker` case (compiler-enforced).
6. `swift test` passes including the new `ColorFormattingTests` suite.
7. `./build.sh` passes (`-warnings-as-errors`).
8. No new Info.plist usage-description key and no `PermissionsService` change — confirms
   `NSColorSampler` needed none.

## D6 — Success feedback (added after owner testing: a silent copy isn't good enough)

D4 originally shipped with no confirmation of what got copied, reasoning that a momentary
button has no toggle to reflect state in — that reasoning held for `URLCleaner` (binary
success/failure, nothing new to show) but not here: a successful pick has a payload, the
actual sampled color, and the owner reported exactly this gap after using the real build.
**Reopen D4 for this one change; everything else in this spec stands.**

Decision: a small transient in-app HUD, not a system notification.

- **Not `UNUserNotificationCenter`.** Ticket 08 already wired that infrastructure, but its
  semantics are "a sustained condition crossed a limit" — a different kind of event, worth
  a permission prompt and a Notification Center entry. A per-tap confirmation for a one-shot
  quick action doesn't warrant asking the user for a system permission on first use, and
  Notification Center / Do Not Disturb / Focus-mode delivery delay would work against the
  "instant, then gone" feel the color picker's whole interaction already has.
- **A borderless `NSPanel` HUD**, in the shape of `ScreenCleanPanel`
  (`Sources/Fluxa/Services/ScreenCleanService.swift`) but far smaller and non-blocking:
  - Content: a small swatch (a filled circle/rounded-rect in the sampled color) beside the
    `#RRGGBB` text in a monospaced font, styled with the existing `FluxaTheme` surface/text
    colors rather than inventing a new palette.
  - `ignoresMouseEvents = true` — it must never intercept a click or steal focus; the user
    may already be doing something else with the color they just copied.
  - Level: `.floating`, not `ScreenCleanPanel`'s `.screenSaverWindow` — it must sit above
    normal windows without blocking full-screen apps or covering the whole display.
  - Position: centered on the screen that contains the mouse pointer at the moment the pick
    completes (`NSScreen.screens.first { $0.frame.contains(mouseLocation) }` falling back to
    `NSScreen.main`), *not* always the main display — the user just clicked a pixel
    somewhere, feedback belongs where they're looking.
  - Lifecycle: fade in, hold ~1.2s, fade out over ~0.3s, then the panel is released. No
    dismiss control, no persistence — this is a HUD, not a window Fluxa needs to track
    state for.
- Shown only on a successful pick (D4's non-nil, successfully-converted color path). Esc
  cancellation and sRGB-conversion failure still produce nothing — there is still no
  useful payload to confirm in either case, D4's reasoning there is unchanged.
- File placement is Codex's call within the existing <500-line-per-file rule: either grow
  `ColorPickerService.swift` with a private HUD presenter, or add a sibling file (e.g.
  `ColorPickerFeedbackWindow.swift`) — whichever keeps `ColorPickerService` focused on the
  sampler/pasteboard responsibility D4 already gave it.

### Updated acceptance (adds to the list above)

9. A successful pick shows the HUD with the correct swatch color and matching hex text,
   automatically dismissing without user interaction, on the screen containing the pointer.
10. The HUD never intercepts a click, never steals key focus, and does not appear on Esc
    cancellation or a failed color-space conversion.

## Out of scope

A format setting (`rgb()`, `NSColor` literal) — no free place to put it, per D1; a future
ticket that gives quick actions a per-row settings surface could revisit this. Undo /
clipboard history. Copying more than one representation at once (e.g. hex + rgb both).
Reusing this HUD mechanism for other momentary actions (`urlCleaner`, `screenSaver`) — worth
considering later, but out of scope for this ticket.
