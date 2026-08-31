# Spec 08 — Threshold alerts on system metrics

Ticket: `issues/08-threshold-alerts.md`
Author: claude
Date: 2026-08-31

## Goal

Fire a local notification when a metric crosses a configured limit, with hysteresis and a
dwell time so a one-sample spike doesn't page the user, and graceful degradation when
notification permission is denied. Everything this needs already exists —
`SystemStatsSampler`, `SystemStatsHistory`, `AppSettings` — this ticket is policy on top,
not new data.

## T1 — `AlertThreshold`: one Codable struct per configured metric, not a settings sprawl

Following disk (`04`) and battery (`06`)'s pattern of extending `SystemMetricID`, adding
alerting is tempting to model as more cases or more flags scattered across
`AppSettings`. It shouldn't be: an alert is genuinely a small record — which metric, which
direction, what limit, is it on — and there can be more than one per metric id in principle
(a user might reasonably want both "CPU above 90%" and, eventually, nothing symmetric for
CPU but definitely "disk below 5 GB free" is a *low* threshold on a metric where high is
normal). One `Codable` struct, stored as a keyed array:

```swift
package struct AlertThreshold: Codable, Identifiable, Sendable, Equatable {
    package let id: UUID
    package var metricID: SystemMetricID
    package var direction: Direction
    package var limit: Double        // in the metric's own unit — % for percentage,
                                      // °C for temperature, bytes for byteCount, etc.
    package var isEnabled: Bool

    package enum Direction: String, Codable, Sendable {
        case above   // fires when value >= limit — CPU, temperature
        case below   // fires when value <= limit — free disk space
    }

    package init(
        id: UUID = UUID(), metricID: SystemMetricID, direction: Direction,
        limit: Double, isEnabled: Bool = true
    ) {
        self.id = id
        self.metricID = metricID
        self.direction = direction
        self.limit = limit
        self.isEnabled = isEnabled
    }
}
```

Lives in `Sources/FluxaCore/Models/AlertThreshold.swift` — a plain value type, no AppKit,
same tier as `SystemMetric.swift`.

**Defaults, one per the ticket's own examples**, seeded on first launch only (same stance
`systemMetricIDs` takes: new features don't retroactively enable themselves for existing
installs, but here the defaults are *disabled by default*, per the ticket's "off switch"
requirement, so nothing fires unless the user turns it on):

```swift
package extension AlertThreshold {
    static let defaults: [AlertThreshold] = [
        AlertThreshold(metricID: .cpuUsage, direction: .above, limit: 90, isEnabled: false),
        AlertThreshold(metricID: .dieTemperature, direction: .above, limit: 90, isEnabled: false),
        AlertThreshold(metricID: .diskFreeSpace, direction: .below,
                       limit: 5 * 1024 * 1024 * 1024, isEnabled: false),
    ]
}
```

`.dieTemperature` over `.cpuTemperature`/`.gpuTemperature` as the default temperature
alert: it's the one reading `unavailableNote` says exists on the widest range of Macs (the
per-component sensors are the ones "this Mac doesn't label per component" applies to), so
it's the default most likely to actually be available to alert on.

## T2 — Persistence: `AppSettings` gains one JSON-encoded array, following its existing
`save(_:forKey:)` shape

Every existing `AppSettings` array is `[String]`. `[AlertThreshold]` doesn't fit that
helper without a new one — encode/decode through `Data`, same `didSet`-writes-through
pattern as everything else in the file:

```swift
var alertThresholds: [AlertThreshold] {
    didSet { saveThresholds(alertThresholds) }
}
```

```swift
// init()
if let data = defaults.data(forKey: Keys.alertThresholds),
   let decoded = try? JSONDecoder().decode([AlertThreshold].self, from: data) {
    alertThresholds = decoded
} else {
    alertThresholds = AlertThreshold.defaults
}
```

```swift
// private
private func saveThresholds(_ value: [AlertThreshold]) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    UserDefaults.standard.set(data, forKey: Keys.alertThresholds)
}
```

`Keys.alertThresholds = "fluxa.alertThresholds"` added alongside the others. This is the
first `Codable`-struct-array in `AppSettings` — every existing one is a flat `[String]` of
raw values — but it's the smallest change that doesn't force every future struct-shaped
setting through a raw-value-array workaround the way `hiddenActionIDs`/`actionOrder` do.

## T3 — Evaluation lives in a new `AlertEvaluator`, not inside `SystemStatsService`

`SystemStatsService` already has one job — sample, publish, keep history — stated
explicitly in its own doc comment as deliberately separate from `AgentUsageService`Bolting
hysteresis/dwell/notification-firing onto it would be the same mistake in miniature: a
second, unrelated responsibility (policy evaluation and OS notification side effects)
riding along on every sampling tick. New `@MainActor` type, owned by `PopoverViewModel` (or
wherever `SystemStatsService` itself is currently owned/started — same lifetime, started
alongside it) rather than by `SystemStatsService`:

```swift
package struct AlertDwellState: Sendable {
    var consecutiveHolding = 0
    var lastFiredAt: Date?
    var isCurrentlyFiring = false   // hysteresis: stays true until the value clears the
                                     // reset band, so a value oscillating right at the
                                     // limit doesn't re-fire every tick
}

@MainActor
final class AlertEvaluator {
    private var dwellStates: [UUID: AlertDwellState] = [:]
    private let notifier: AlertNotifying

    init(notifier: AlertNotifying = SystemAlertNotifier()) {
        self.notifier = notifier
    }

    /// Called every sample tick with the current readings and the user's configured
    /// thresholds. `intervalSeconds` is the *current* sampling interval — dwell is
    /// expressed in seconds so it means the same wall-clock duration regardless of
    /// whether Customize is set to sample every 1s or every 10s.
    func evaluate(
        sample: SystemStatsSample,
        thresholds: [AlertThreshold],
        intervalSeconds: TimeInterval
    ) {
        let dwellSamplesRequired = max(1, Int((Self.dwellSeconds / intervalSeconds).rounded()))

        for threshold in thresholds where threshold.isEnabled {
            guard let value = sample.value(for: threshold.metricID) else {
                dwellStates[threshold.id] = nil   // metric vanished (unplugged disk, etc.) —
                                                    // don't carry stale dwell progress into
                                                    // whenever it comes back
                continue
            }
            var state = dwellStates[threshold.id] ?? AlertDwellState()
            let isHolding = threshold.direction.isCrossed(value: value, limit: threshold.limit)
            let hasCleared = threshold.direction.hasCleared(
                value: value, limit: threshold.limit, resetBand: Self.resetBand
            )

            if isHolding {
                state.consecutiveHolding += 1
            } else {
                state.consecutiveHolding = 0
            }

            if hasCleared {
                state.isCurrentlyFiring = false
            }

            if state.consecutiveHolding >= dwellSamplesRequired, !state.isCurrentlyFiring {
                state.isCurrentlyFiring = true
                state.lastFiredAt = Date()
                notifier.notify(metricID: threshold.metricID, value: value, limit: threshold.limit)
            }

            dwellStates[threshold.id] = state
        }
    }

    /// How long a condition must hold before it fires. Fixed here rather than per-threshold —
    /// same "don't over-build the knob" call `05`'s network allowlist and `06`'s debounce
    /// constants made; a single sitewide dwell is enough to solve the spam problem the ticket
    /// names, and per-threshold tuning is a bigger feature than this ticket needs to be.
    static let dwellSeconds: TimeInterval = 30

    /// How far the value must retreat past the limit, as a fraction of the limit, before the
    /// alert is armed to fire again. 10% of the limit — a CPU alert at 90% re-arms once usage
    /// drops below 81%; not so close to 90% that ordinary noise re-fires it, not so far that a
    /// real second spike goes unreported for a long stretch.
    static let resetBand: Double = 0.10
}
```

```swift
package extension AlertThreshold.Direction {
    func isCrossed(value: Double, limit: Double) -> Bool {
        switch self {
        case .above: return value >= limit
        case .below: return value <= limit
        }
    }

    func hasCleared(value: Double, limit: Double, resetBand: Double) -> Bool {
        switch self {
        case .above: return value < limit * (1 - resetBand)
        case .below: return value > limit * (1 + resetBand)
        }
    }
}
```

`dwellSamplesRequired` is recomputed from the *current* interval on every `evaluate` call
rather than cached — cheap, and it means a mid-session interval change (Customize) takes
effect on the very next tick, matching how `SystemStatsService.runLoop()` already re-reads
`interval()` every iteration instead of capturing it once.

**Why hysteresis is reset-band-on-value, not a second dwell timer**: a symmetric "must also
stay clear for N seconds before re-arming" would solve flapping too, but it means a real,
sustained recovery still leaves the alert silently "primed but muted" for a window the user
has no visibility into. A value-based reset band re-arms the instant the value has
genuinely moved away from the limit by a meaningful margin — no hidden timer, no state that
silently expires.

## T4 — `AlertNotifying` / `SystemAlertNotifier`: the `UNUserNotificationCenter` boundary

This is the first thing in Fluxa to touch `UserNotifications` — grep confirms no existing
call site. Protocol-isolate it so `AlertEvaluator` above is testable without a real
notification center (Antigravity's unit tests exercise the dwell/hysteresis state machine
against a fake):

```swift
package protocol AlertNotifying: Sendable {
    func notify(metricID: SystemMetricID, value: Double, limit: Double)
}
```

```swift
import UserNotifications

final class SystemAlertNotifier: AlertNotifying, Sendable {
    func notify(metricID: SystemMetricID, value: Double, limit: Double) {
        let content = UNMutableNotificationContent()
        content.title = "\(metricID.title) alert"
        content.body = "\(metricID.title) is at \(SystemMetric(id: metricID, value: value).displayText)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fluxa.alert.\(metricID.rawValue)",
            content: content,
            trigger: nil   // fire immediately
        )
        // Fire-and-forget, matching PermissionsService's stance toward the several other
        // system prompts it drives: a denial here is silently absorbed by
        // UNUserNotificationCenter itself (no delivery, no error surfaced to us) once
        // authorization has already been checked at the point the user turned the alert on —
        // see T5. Re-checking authorization on every fire would mean two round trips into
        // UserNotifications per alert for no behavioral difference.
        UNUserNotificationCenter.current().add(request)
    }
}
```

Re-using the same `identifier` per metric (rather than a fresh UUID per fire) means a
second notification for the same still-firing metric *replaces* the first in Notification
Center instead of stacking duplicates — the right behavior given the hysteresis in T3
already prevents rapid re-fires, but a Mac that was asleep across two separate alert
episodes shouldn't leave a pile of stale, identical-looking banners.

## T5 — Authorization: ask lazily, follow `PermissionsService`'s pattern, degrade visibly

The ticket requires (a) asking only when the user enables the first alert, never at launch,
and (b) visible degradation on denial, not silent failure. `PermissionsService` already
establishes both stances for Accessibility/Automation/Bluetooth — extend it rather than
inventing a second permissions pattern:

```swift
// PermissionsService additions
private(set) var notifications: FluxaPermissionStatus = .notRequested

func requestNotifications() async {
    guard busyPermission == nil else { return }
    message = nil
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional:
        notifications = .granted
        return
    case .denied:
        notifications = .denied
        openSettings("Privacy_Notifications")
        return
    default: break
    }
    busyPermission = "notifications"
    defer { busyPermission = nil }
    do {
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        notifications = granted ? .granted : .denied
        if !granted {
            message = "Notifications were not enabled. Alerts will stay silent until you allow "
                + "them in Privacy & Security → Notifications."
        }
    } catch {
        notifications = .denied
        message = error.localizedDescription
    }
}
```

**Where this is called from**: the Customize UI for alert thresholds (a new section, not
specified in detail here — it's a UI-layer ticket detail, follows whatever row/toggle
pattern the existing Customize sections already use) calls `requestNotifications()` the
first time the user flips an `AlertThreshold.isEnabled` from false to true, not when the
threshold row is merely displayed or edited.

**Degradation, concretely**: `AlertEvaluator` does not gate on permission status at all —
it always evaluates and always calls `notifier.notify(...)` when a threshold fires;
`UNUserNotificationCenter` silently drops undelivered notifications when unauthorized, per
Apple's own documented behavior, so no separate no-op path is needed in `AlertEvaluator`
itself. What must not happen is the *toggle* looking like it succeeded with no indication
anything is wrong. Customize's threshold row shows `PermissionsService.notifications`
status next to the enabled toggle (reusing `FluxaPermissionStatus.title` — "Not allowed" /
"Allowed" / "Not enabled" — the same strings every other permission row already renders),
so a denied user sees their alert is configured but silenced, not just nothing.

## T6 — Wiring: where `evaluate` gets called

`AlertEvaluator.evaluate(sample:thresholds:intervalSeconds:)` is called once per completed
sample, from the same place that currently calls `SystemStatsService.apply(_:)` — i.e.
`SystemStatsService` gains a lightweight hook rather than owning the evaluator itself,
keeping the separation from T3:

```swift
// SystemStatsService
var onSample: (@MainActor (SystemStatsSample) -> Void)?

private func apply(_ sample: SystemStatsSample) {
    ...
    onSample?(sample)
}
```

Whoever constructs `SystemStatsService` (the popover/menu-bar owner) wires:

```swift
systemStatsService.onSample = { [weak alertEvaluator, settings] sample in
    alertEvaluator?.evaluate(
        sample: sample,
        thresholds: settings.alertThresholds,
        intervalSeconds: settings.systemStatsInterval.seconds
    )
}
```

This keeps `SystemStatsService` ignorant of alerting entirely — it publishes samples the
way it always has, to as many observers as care to attach, the same shape
`AgentUsageService`-adjacent code presumably already uses for its own consumers.

## Acceptance

1. `AlertThreshold` (Codable, `Sendable`, `Identifiable`) exists in `FluxaCore/Models`,
   with the three example defaults from T1, all `isEnabled: false` out of the box.
2. `AppSettings.alertThresholds` persists via JSON in `UserDefaults`, migrates a missing
   key to the defaults, never crashes on a corrupt/undecodable stored value (falls back to
   defaults instead).
3. `AlertEvaluator` fires at most once per threshold per "episode" — dwell (30s worth of
   samples) must hold before the first fire, and a fired threshold does not fire again
   until the value has cleared the 10% reset band.
4. Changing `SystemStatsInterval` mid-session changes how many samples the dwell window
   needs without a restart.
5. `PermissionsService.requestNotifications()` follows the same lazy-ask, denial-visible
   pattern as its Accessibility/Automation/Bluetooth counterparts; never called except from
   the moment a threshold's toggle turns on.
6. A denied Notifications permission does not crash, does not silently retry, and is
   visible in the Customize threshold row via the existing `FluxaPermissionStatus` display.
7. `swift test`, `swift build`, `./build.sh` pass; no new strict-concurrency warnings; no
   `public` in `FluxaCore`. `AlertEvaluator`'s dwell/hysteresis logic is unit-testable
   against a fake `AlertNotifying` without touching real `UserNotifications` state.
8. Local build launched per `docs/agents/roles.md` — owner can enable a threshold, grant
   notification permission, and manually trigger the condition (e.g. a CPU-bound loop) to
   see a real banner.

## Out of scope

A full Customize UI for adding/removing/editing arbitrary thresholds beyond the three
seeded defaults — T1's defaults are enough to prove the mechanism; a "create a custom
threshold on any metric" builder is a reasonable follow-up once the pipeline is proven, not
a blocker for this ticket. Per-threshold configurable dwell/reset-band (T3's rationale).
Alerting on `.batteryLevel`/`.batteryTimeRemaining` (ticket `06`, may not even be merged
first) or `.byteRate` metrics — nothing here prevents adding a `.below`/`.above` default for
them later, it's simply not in the seed list.

## Risks

- **`UNUserNotificationCenter.current()` requires the process to have a valid, registered
  bundle identifier and, in some configurations, the app to be signed** — this should be a
  non-issue given Fluxa already ships as a signed `.app` bundle with `CFBundleIdentifier`
  set, but Antigravity should confirm notifications actually deliver from the repo-root
  local build, not just from an `/Applications`-installed copy, since sandboxing/signing
  quirks sometimes differ between the two. If they don't fire from the local build, treat
  it as a needs-info back to this spec, not a silent skip.
- **Dwell math with `Int((30 / intervalSeconds).rounded())`**: at `SystemStatsInterval
  .tenSeconds` this rounds to 3 samples; fine. Confirm there's no path where
  `intervalSeconds` could be `0` (it can't — `SystemStatsInterval.seconds` is a fixed
  enum-backed constant, never user-typed) that would divide by zero.
- **`AlertDwellState` keyed by `UUID`, not by `SystemMetricID`**: intentional, so a future
  UI allowing two thresholds on the same metric (e.g. a warning-level and a critical-level
  CPU alert) doesn't collide on dwell state — flagging so nobody "simplifies" the key to
  `SystemMetricID` during implementation and quietly breaks that future case.
