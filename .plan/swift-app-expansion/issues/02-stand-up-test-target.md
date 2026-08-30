# 02 — Stand up a test target

Status: ready-for-handoff
Owner: —
Type: task
Spec: specs/02-stand-up-test-target.md
Blocked by: —
Source: —

## Question

`Package.swift` declares a single `executableTarget` and no `testTarget`.
`Tests/FluxaScreenshots/` exists but is empty, so `swift test` does nothing today.

Antigravity cannot validate anything until this is fixed, so every ticket is blocked at
`antigravity-validation` behind this one.

Decide and implement:

- Whether to test the executable target directly, or extract a library target that both
  the executable and the tests depend on. The executable uses
  `-parse-as-library` and `@main`, and linking an executable target into tests is awkward
  — the library split is likely the right answer, but it is a real architectural change
  and needs Claude's design, not an ad-hoc edit.
- Swift Testing or XCTest. Nothing is established yet, so this is a free choice;
  Swift Testing is the better default on macOS 14 / Swift 5.9+.
- What `Tests/FluxaScreenshots/` was meant to be — delete it or fill it.

## Notes

This is scaffolding, not ported behaviour. Keep it separable from the vorssaint-utils
work so a survey outcome in ticket `01` can't invalidate it.

## Answer

Validated 2026-08-30 by Antigravity:

1. **Test Execution**: `swift test` successfully executes Swift Testing suite `FluxaCoreTests` with 3 passed tests (0 failures).
2. **Build Verification**: `swift build` builds cleanly.
3. **Packaging / Release Build**: `./build.sh` produces signed release `Fluxa.app` under strict `-Xswiftc -warnings-as-errors`.
4. **Strict Concurrency**: `swift build -Xswiftc -strict-concurrency=complete` introduces zero new warnings (only 1 pre-existing warning in `MemorySampler.swift` regarding Darwin `vm_kernel_page_size` in `FluxaCore`, and pre-existing warnings in `Fluxa`).
5. **Encapsulation & Access Control**: Checked `grep -rn "^public \|	public " Sources/FluxaCore` — returned 0 matches; all exposed core symbols use `package` access strictly.
6. **Retain Cycle Audit**: All moved types are structs, enums, or actor (`SystemStatsSampler`) without escaping closures or retain cycles.
7. **Purity of Diff**: Verified zero logic changes across the 11 moved files and 22 importing files.

Acceptance criteria fully satisfied.

## Comments

- 2026-08-30, claude — Spec written. Decisions: minimal `FluxaCore` library (11 already-pure
  files), `package` access rather than `public`, `@testable import` in tests, Swift Testing,
  delete the empty untracked `Tests/FluxaScreenshots/`.
  Verified on a scratch package at `swift-tools-version: 5.9` with this toolchain
  (Swift 6.2.4): `package` crosses the module boundary, `@testable` reaches `internal`,
  and Swift Testing runs with no added dependency. None of these are assumptions.
  Watch `build.sh` — it compiles with `-Xswiftc -warnings-as-errors`, so a new warning
  breaks packaging, not just the tests.
- 2026-08-30, codex — Implemented D1–D5 and handed off to Antigravity. Touched
  `Package.swift`; moved the 11 specified files to `Sources/FluxaCore/`:
  `Models/SystemMetric.swift`, `Models/SystemStatsHistory.swift`,
  `Models/SystemStatsInterval.swift`, `Models/UsageRefreshInterval.swift`,
  `Models/AgentUsage.swift`, `Services/FluxaError.swift`, and
  `Services/SystemStats/{CPUUsageSampler,GPUUsageSampler,MemorySampler,SystemStatsSampler,ThermalSensorReader}.swift`.
  Added compiler-requested `package` access only in those moved files; the four concrete sampler
  implementations remain internal. Added `Tests/FluxaCoreTests/FluxaCoreTests.swift` and removed the
  empty untracked `Tests/FluxaScreenshots/` directory. The executable files touched only to import
  the new module were `Models/AppSettings.swift`;
  `Services/{AgentUsageReaders,AgentUsageService,AudioOutputService,BluetoothAudioService,DesktopIconService,FocusModeService,KeepAwakeService,MicrophoneMuteService,ScreenSaverService,ShellRunner,SystemStatsService}.swift`;
  and `Views/{AgentUsageStripView,AgentUsageWindowView,ControlDeckDashboardView,ControlDeckMetricsView,ControlDeckTheme,CustomizeAgentUsageSection,CustomizeSystemStatsSection,MenuBarStripRenderer,SystemStatsStripView,SystemStatsWindowView}.swift`.
  This ticket file is the only other touched file.

  Acceptance: `swift test` passed with 3 Swift Testing tests in 1 suite; `swift build` passed;
  `./build.sh` passed with warnings-as-errors and recreated the existing ignored local `Fluxa.app`
  (2.6.2 build 13, arm64, strict code-sign verification passed) without install, launch, update-key
  access or publication. The requested pre-change strict-concurrency warning count was 134. A full
  isolated post-change rebuild counted 106; an additional fresh `HEAD` versus current comparison
  counted 135 versus 106 and found no new unique warning message. The acceptance `grep` for `public`
  under `Sources/FluxaCore` returned no output. Per-file comparison against `HEAD` found no logic
  changes: only moves, compiler-driven `package` modifiers/initializers, imports, manifest changes,
  and the specified tests.

  The only item not explicit in the spec was the need to add `import FluxaCore` to the 22 executable
  source files that reference moved declarations; Swift imports are file-scoped. No D1–D5 decision
  needed revision, and neither `UpdateService` nor any Sparkle source/wiring was touched.
- 2026-08-30, antigravity — Validation complete. Ran `swift test` (3/3 passed), verified `swift build` and `./build.sh` (passed clean with `-warnings-as-errors`), checked strict concurrency (`swift build -Xswiftc -strict-concurrency=complete`, 0 new warnings), confirmed zero `public` annotations under `Sources/FluxaCore/`, verified retain-cycle absence, and confirmed structural diff purity. Status advanced to `ready-for-handoff`.

