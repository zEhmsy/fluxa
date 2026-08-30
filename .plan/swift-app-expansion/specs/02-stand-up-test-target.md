# Spec 02 — Stand up a test target

Ticket: `issues/02-stand-up-test-target.md`
Author: claude
Date: 2026-08-30

## Goal

Make `swift test` do something. Today `Package.swift` declares one `executableTarget` and
no `testTarget`, so every ticket in this effort is blocked at `antigravity-validation`.

This is scaffolding. **No behaviour changes.** No file's logic is edited; files move and
gain access modifiers, nothing else.

## Decisions

### D1 — Extract a minimal `FluxaCore` library target

The executable carries `-parse-as-library`, `@main`, and linker flags that embed
`Info.plist` into `__TEXT,__info_plist` plus an `@executable_path/../Frameworks` rpath.
Those must not be applied to a test bundle, so the test target does **not** depend on the
executable. Instead the already-pure code moves to a library both can depend on.

Move these 11 files from `Sources/Fluxa/` to `Sources/FluxaCore/`, preserving their
subpaths. Every one already imports only Foundation/Darwin/IOKit and contains **zero**
`@MainActor`:

```
Models/SystemMetric.swift            SystemMetricID, SystemMetric
Models/SystemStatsHistory.swift      SystemStatsHistorySample
Models/SystemStatsInterval.swift     SystemStatsInterval
Models/UsageRefreshInterval.swift    UsageRefreshInterval
Models/AgentUsage.swift              AgentUsageMetric
Services/FluxaError.swift            FluxaError
Services/SystemStats/CPUUsageSampler.swift
Services/SystemStats/GPUUsageSampler.swift
Services/SystemStats/MemorySampler.swift
Services/SystemStats/SystemStatsSampler.swift    SystemStatsSample, SystemStatsSampler
Services/SystemStats/ThermalSensorReader.swift
```

This is exactly the surface tickets `03`–`08` touch. The boundary can grow one file at a
time later; do not widen it in this ticket.

`AppSettings`, `SystemStatsService` and everything UI-facing **stay in the executable**.
They are `@MainActor`/`@Observable` and moving them is a separate decision.

### D2 — Cross-module access uses `package`, never `public`

`package` (SE-0386, available at `swift-tools-version: 5.9`) makes a symbol visible to
other targets **in the same package** without publishing it as library API. Verified
working on this toolchain (Swift 6.2.4) against a 5.9 tools-version package.

- Annotate `package` on exactly the declarations the executable references across the
  boundary — types, their `package init`, and only the members actually used.
- **Do not use `public` anywhere in this ticket.** `public` creates an API surface with
  resilience implications that this package neither needs nor wants.
- Leave everything else `internal`. Under-annotate and let the compiler tell you what is
  missing; do not blanket-annotate the files.

### D3 — Tests use `@testable import`, so they need no annotations

`@testable import FluxaCore` gives the test target `internal` access. Verified. So the
`package` work in D2 is driven **solely** by what the Fluxa executable needs, never by
what a test wants to reach. If a test needs a symbol, `@testable` already covers it.

### D4 — Swift Testing, not XCTest

Toolchain is Swift 6.2.4 / Xcode 26.3; Swift Testing is bundled and needs no package
dependency. Verified running. Nothing established otherwise in this repo, so this is a
free choice and Swift Testing is the better default.

### D5 — Delete `Tests/FluxaScreenshots/`

Empty, untracked, never committed, referenced nowhere in sources, `build.sh`, or docs.
It is a local leftover. Remove it; do not preserve the name.

## Resulting `Package.swift`

```swift
targets: [
    .target(
        name: "FluxaCore",
        path: "Sources/FluxaCore"
    ),
    .executableTarget(
        name: "Fluxa",
        dependencies: [
            .product(name: "Sparkle", package: "Sparkle"),
            "FluxaCore",
        ],
        path: "Sources/Fluxa",
        // exclude / resources / swiftSettings / linkerSettings unchanged
    ),
    .testTarget(
        name: "FluxaCoreTests",
        dependencies: ["FluxaCore"],
        path: "Tests/FluxaCoreTests"
    ),
]
```

`FluxaCore` gets **no** `unsafeFlags` and **no** `linkerSettings`. Those belong to the
executable and are the reason this split exists.

## Seed tests

Enough to prove the harness runs, not to cover the samplers — that is Antigravity's work
on later tickets. Do not gold-plate.

- `SystemMetricID` raw values are stable. `AppSettings` persists them, and the source says
  renaming a case must not silently drop a user's selection. Assert each case's raw string
  literally, so a rename fails the build rather than a user's config.
- `SystemStatsSample.empty` has every field `nil`.
- `MemorySampler().sample()` returns a value in `0...100` or `nil` — it must never throw or
  trap on this machine.

## Acceptance

1. `swift test` runs and passes, reporting a non-zero test count.
2. `swift build` passes.
3. `./build.sh` still produces a working `Fluxa.app`. It compiles release/arm64 with
   `-Xswiftc -warnings-as-errors`, so **any new warning breaks the release build** —
   check this explicitly, it is the most likely way this ticket silently breaks something.
4. `swift build -Xswiftc -strict-concurrency=complete` introduces no *new* warnings versus
   the pre-change baseline. Record the baseline before moving files. Reducing them is not
   required here.
5. `grep -rn "^public \|	public " Sources/FluxaCore` returns nothing.
6. No file's logic changed. The diff is moves, `package` modifiers, and `Package.swift`.

## Out of scope

Enabling Swift 6 language mode. Fixing pre-existing concurrency warnings. Moving
`AppSettings` or any `@MainActor` type. Writing sampler test coverage.

## Risks

- **`-warnings-as-errors` in `build.sh`.** A moved file that emits a new warning in a new
  module context breaks packaging, not just tests. Acceptance criterion 3 exists for this.
- **Over-annotation.** The tempting shortcut is to mark every declaration `package` or
  `public` at once. It produces a large meaningless diff and hides which symbols actually
  cross the boundary. Let the compiler drive.
- **Scope creep into ticket 03.** `SystemMetricID` is about to change shape in `03`. Do not
  anticipate that here — move it as-is.
