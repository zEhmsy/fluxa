# Spec 16 — Two-column strip layout

Ticket: `issues/16-strip-two-column-layout.md`
Author: claude, 2026-09-05

Let both popover strips wrap onto a second row, and raise the System reading cap to four.

## D1 — One layout, used by both strips

`AgentUsageStripView` and `SystemStatsStripView` are siblings by design; `SystemStatsStripView`'s
own header comment says so. The wrapping therefore goes in a single small view that both call,
not into each strip separately.

Add `Sources/Fluxa/Views/MetricChipGrid.swift`:

```swift
struct MetricChipGrid<Item: Identifiable, Chip: View>: View {
    let items: [Item]
    @ViewBuilder let chip: (Item) -> Chip
}
```

It owns only the arrangement — spacing, rows, and the odd-chip rule. Chip content, colours, meters,
tooltips and accessibility stay in the two strips exactly as they are today. Nothing about a chip's
appearance moves.

Both strips replace their `HStack(spacing: 10) { ForEach(metrics) { chip(for: $0) } }` with
`MetricChipGrid(items: metrics) { chip(for: $0) }`. Every modifier outside that `HStack` — the
padding, the background, the border, the `Button` wrapper — is untouched.

`SystemMetric` and `AgentUsageMetric` are both already `Identifiable`; if either is not, make it so
rather than passing indices.

## D2 — The wrapping rule

At most two chips per row. The final chip of an odd count spans the full width of its own row.

| Chips | Layout |
| ----- | ------ |
| 1     | one row, one full-width chip |
| 2     | one row, two chips |
| 3     | two rows: 2, then 1 full-width |
| 4     | two rows: 2 + 2 |

Three as `2 + 1` rather than three narrow columns is the point of the ticket — three columns is the
state the owner reported as unreadable. The lone third chip taking the full width is deliberate: an
odd chip padded to half width with empty space beside it reads as a missing chip.

Horizontal spacing stays `10`, matching today. Row spacing is `8` — slightly tighter than the
horizontal gap, so the block reads as one panel rather than two stacked strips.

## D3 — One and two chips must not change at all

A single row is not a special case of the grid; it is the existing behaviour and must be preserved
bit for bit, including height. Users who select one or two readings did not ask for a taller
popover and must not get one.

Concretely: for `items.count <= 2` the grid emits exactly one `HStack(spacing: 10)` of
`.frame(maxWidth: .infinity)` chips — the same view tree as today. Verify by opening the popover
with two System readings selected before and after the change; the popover height must be identical.

## D4 — `maxSystemMetrics` rises to 3 → 4

`AppSettings.maxSystemMetrics` becomes `4`. Its doc comment currently says "How many system chips
fit the popover strip on one row" — that sentence is now false and must be rewritten to describe the
two-row block.

Two call sites read it and both already use the constant rather than a literal:
`CustomizeSystemStatsSection.swift:151` (the selection guard) and the section's hint text. Check the
hint's wording still reads correctly with "4"; if it says "on one row", fix it.

`selectedMetrics(ids:)` must not silently return more than the cap. If it does not clamp today, it
still does not need to — the guard is in Customize — but confirm rather than assume, because a
settings file carried over from a build with a different cap is a real input.

## D5 — `maxUsageMetrics` stays at 3

The owner asked for four readings in System, not in Agent usage. Do not raise
`AppSettings.maxUsageMetrics`.

This is a deliberate asymmetry, not an oversight: Antigravity alone exposes four pools, so a cap of
four on the agent strip invites a strip that is four Antigravity meters and no Claude. Three is a
better default there. The grid supports four either way, so raising it later is a one-character
change if the owner asks.

## D6 — Accessibility and hit target

The strip is one `Button`; the chips are not individual targets. That does not change. The
`accessibilityValue` already reads the metrics in order and needs no edit — the grid changes where
chips are drawn, not the order of `metrics`.

## Testing

The strips are SwiftUI views in the `Fluxa` executable target, which has no test coverage and is not
importable by `FluxaCoreTests`. Do not invent a view test target for this.

What must be checked, by hand, before the ticket moves on:

1. Each of 1, 2, 3, 4 System readings selected — layout matches D2's table.
2. Two readings: popover height unchanged from the previous build (D3).
3. Agent usage with three chips including at least two from one provider, so the window initial is
   present — the initial must no longer crowd the percentage.
4. Both strips visible at once, four System readings and three agent chips, in light and dark
   appearance: the two blocks still read as one stack.
5. `./build.sh` clean, and the existing suite still green.

If any pure logic falls out of the grid — a row-splitting function, for instance — put it in
`FluxaCore` and test it there. Do not force it: the arrangement is small enough that a view-local
computed property is honest.
