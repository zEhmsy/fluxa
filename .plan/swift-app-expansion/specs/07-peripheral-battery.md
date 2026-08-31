# Spec 07 — Peripheral battery levels

Ticket: `issues/07-peripheral-battery.md`
Author: claude
Date: 2026-08-31

## Goal

Battery percentage for connected HID peripherals — Magic Mouse, Magic Keyboard, Magic
Trackpad, and third-party Bluetooth accessories that report the same way — shown as a
list, since unlike every other metric in this effort there can be zero, one, or several at
once. A device that reports no battery is absent from the list, never shown at 0%. A
briefly-dropped device does not flicker in and out.

## Q1 — Not `BluetoothAudioService`, and not `IOBluetoothDevice` at all: reuse `06`'s API

The ticket suggests three candidate sources and asks to read `BluetoothAudioService`
first rather than duplicate it. Read it (`Sources/Fluxa/Services/BluetoothAudioService.swift`)
— it enumerates `IOBluetoothDevice.pairedDevices()`, filtered to the Audio/Video device
class, for AirPods/headphones connect-toggling. It has no battery reading today, and
`IOBluetoothDevice`'s public header (`IOBluetoothDevice.h`) does not declare a battery
property at all — the value AirPods show in Control Center comes from a separate, private,
undocumented subsystem. Building on `IOBluetoothDevice` here would mean either leaving
battery unimplemented for exactly the devices `BluetoothAudioService` manages, or reaching
for the same class of undocumented private selector this effort's own rejected list
(`map.md` → alt-tab switcher, Dock preview) already ruled out for being private API. Not
extending `BluetoothAudioService` is the correct call, not an oversight.

**What actually works, and is already in this codebase**: ticket `06`'s `BatterySampler`
calls `IOPSCopyPowerSourcesList`, a fully public, documented `IOKit.ps` API, and reads
`sources.first` — the internal battery. That call returns **every** power source macOS
knows about, not just the internal one. On real hardware, a paired-and-connected Magic
Mouse/Keyboard/Trackpad — and some third-party Bluetooth HID accessories that implement the
standard Bluetooth LE Battery Service — appear as additional entries in that same list,
distinguishable by `kIOPSTransportTypeKey` (`"Bluetooth"`, vs `"Internal"` for the Mac's own
battery) and `kIOPSNameKey` (the product name). This is the exact mechanism macOS's own
System Settings → Bluetooth battery percentages come from for these devices. `06`'s own
spec flagged this directly: *"multiple entries in the list only happen with external UPS
devices or Bluetooth accessories, which is exactly ticket `07`'s scope... deliberately not
generalized here."* This ticket is that generalization.

**AirPods (and Bluetooth audio headsets generally) do not appear in this list.** Their
battery reporting is a different, non-`IOPSPowerSource` subsystem with no public API this
effort has found. Per Q3, they're out of scope here — not silently dropped, explicitly
decided against for the same private-API reason as the rest of the Rejected list.

## Q2 — Model: a list, not a `SystemMetricID`

Every other metric in this group is "the Mac has exactly one of these, or none." Peripheral
battery is "the Mac has zero or more of these, and which ones is itself information."
Forcing it through `SystemMetricID`/`SystemStatsSample`'s one-scalar-per-id dictionary
would need a variable number of synthetic ids invented per session — doesn't fit. This is
its own model and its own service, parallel to `BluetoothAudioService`, not folded into
`SystemStatsSampler`.

```swift
package struct PeripheralBatteryReading: Identifiable, Sendable, Equatable {
    package let id: String        // kIOPSHardwareSerialNumberKey when present, else name —
                                    // stable across samples for the same physical device
    package let name: String      // kIOPSNameKey, e.g. "Magic Trackpad"
    package let level: Int        // kIOPSCurrentCapacityKey, 0...100
    package let isCharging: Bool  // kIOPSIsChargingKey, false if the key is absent
}
```

`FluxaCore/Services/SystemStats/` is the wrong home — it's not a `SystemStatsSampler`
constituent and doesn't feed `SystemStatsSample`. New file:
`Sources/FluxaCore/Services/PeripheralBatterySampler.swift`, `package`-visible, same tier
as `BatterySampler` but standalone.

```swift
package struct PeripheralBatterySampler {
    package init() {}

    /// Every non-internal power source with a readable battery level. Order matches
    /// whatever IOKit returns — the caller sorts for display.
    package func sample() -> [PeripheralBatteryReading] {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }

        return sources.compactMap { source -> PeripheralBatteryReading? in
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any]
            else { return nil }

            // Excludes the internal battery by transport type, not by position — `06`
            // reads `sources.first` assuming it's always the internal battery; that's an
            // ordering assumption IOKit's docs don't actually guarantee. This sampler
            // doesn't repeat it: filtering on the transport key is correct regardless of
            // list order, and is the fix if `06`'s assumption ever turns out wrong (see
            // Risks).
            let transport = description[kIOPSTransportTypeKey] as? String
            guard transport != kIOPSInternalType else { return nil }

            guard let level = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue,
                  (0...100).contains(level)
            else { return nil }

            let name = (description[kIOPSNameKey] as? String) ?? "Unknown accessory"
            let id = (description[kIOPSHardwareSerialNumberKey] as? String) ?? name
            let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false

            return PeripheralBatteryReading(id: id, name: name, level: level, isCharging: isCharging)
        }
    }
}
```

A source present in the list but missing a usable `kIOPSCurrentCapacityKey` is dropped by
the `compactMap`, not surfaced as a zero — that's the ticket's "absent, not 0%" rule
enforced at the sampler boundary, same stance `BatterySampler`/`DiskSpaceSampler` already
take.

## Q3 — Explicitly out of scope: AirPods and Bluetooth audio battery

Named here rather than left implicit, since the ticket asks for AirPods by name. No public
API surfaced during this design pass. If one exists, it isn't `IOPSCopyPowerSourcesList`
(verified: AirPods do not appear in it during normal use) and isn't a documented method on
`IOBluetoothDevice`. Chasing this further means either private-selector calls this effort's
own policy rejects, or an undocumented IORegistry class/key discovered by inspection with
no Apple documentation behind it — a materially different risk profile than `06`'s
`kIOPS*` keys (all real constants from a public header) or `04`'s `Statistics` dictionary
keys (undocumented values, but read through a fully public, intended-for-this-purpose
IOKit call). If the owner wants to pursue it anyway, that's a `needs-info` decision, not an
engineering default — flag and stop, per `AGENTS.md`'s clean-room/private-API rule, rather
than quietly shipping a fragile private call.

## Q4 — `PeripheralBatteryService`: presence hysteresis, not value hysteresis

The ticket's other explicit requirement — "design the refresh so a disconnected device
doesn't churn the popover" — is a different problem from `06`'s value-jumpiness: here the
number itself (once present) is stable; what's unstable is *whether the entry exists at
all* from one sample to the next, since a peripheral asleep or briefly out of range can
drop out of `IOPSCopyPowerSourcesList` for one pass and reappear the next.

`@MainActor` service, `Sources/Fluxa/Services/PeripheralBatteryService.swift`, following
`BluetoothAudioService`'s shape (a plain `refresh()`-driven service, not a polling actor —
peripheral battery changes over hours, not seconds, so there's no case for
`SystemStatsSampler`'s tight loop here):

```swift
@Observable
@MainActor
final class PeripheralBatteryService {
    private(set) var devices: [PeripheralBatteryReading] = []

    private let sampler = PeripheralBatterySampler()
    private var missingStreak: [String: Int] = [:]   // id -> consecutive absent samples

    /// A device must be missing this many consecutive refreshes before it's dropped from
    /// `devices` — one dropped sample is noise, not a disconnect.
    private static let missingThreshold = 2

    func refresh() {
        let current = sampler.sample()
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })

        for id in missingStreak.keys where currentByID[id] == nil {
            missingStreak[id, default: 0] += 1
        }
        for id in currentByID.keys {
            missingStreak[id] = 0
        }
        missingStreak = missingStreak.filter { $0.value < Self.missingThreshold }

        // Keep the last known reading for anything still inside its grace period, so the
        // row doesn't blink out and back with a possibly-different position in the list.
        let retained = devices.filter { device in
            currentByID[device.id] == nil && (missingStreak[device.id] ?? Self.missingThreshold) < Self.missingThreshold
        }
        let merged = Dictionary(uniqueKeysWithValues: (current + retained).map { ($0.id, $0) })

        devices = merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
```

This mirrors `06`'s stance (don't publish a value that hasn't earned trust yet) applied to
presence instead of magnitude: a device is removed from `devices` only after two
consecutive misses, and a device that reappears within its grace window keeps its
last-known level rather than blinking to a fresh read one tick later — acceptable since the
level itself changes slowly and a stale-by-one-refresh percentage is a smaller error than a
disappearing/reappearing row.

**Refresh cadence**: called from wherever the popover/dashboard already calls
`BluetoothAudioService.refresh()` on open (same trigger), plus, unlike
`BluetoothAudioService`, a slow background timer — battery percentage on a peripheral is
worth updating even while the popover is closed for a dashboard/menu-bar chip, but at a
cadence nowhere near `SystemStatsInterval`'s 1–10s range. A fixed 60-second `Task.sleep`
loop, started once and never following `SystemStatsInterval`, is enough: peripheral battery
doesn't drain fast enough for a tighter loop to matter, and decoupling it from
`SystemStatsInterval` keeps this feature's cost independent of a setting that exists to
tune a completely different sampler's overhead.

## Q5 — No `AppSettings`/permission changes needed

`IOPSCopyPowerSourcesList` needs no Bluetooth/CoreBluetooth authorization — it's a
system-level power-source query, the same call `06`'s `BatterySampler` already makes today
without touching `PermissionsService.bluetooth` at all. `PeripheralBatteryService` doesn't
gate on `BluetoothAudioService.hasPermission`; the two are unrelated despite both involving
Bluetooth hardware. Selecting which devices to show is not exposed as a
Customize toggle in this ticket — the list is simply "whatever's connected," same
posture `BluetoothAudioService.devices` already takes for its own list.

## Q6 — UI placement: a "Peripherals" panel in `SystemStatsWindowView`, shown only when non-empty

Left unresolved in the first pass of this spec, and rightly flagged back by Codex: the
Goal calls for the list to be shown, and Acceptance requires the owner to actually see a
real percentage after pairing a device, which cannot be satisfied by a model/service with
no view wired to it. Deciding this now rather than escalating to the owner — it's a small,
low-risk placement call, not a product-shape decision.

`SystemStatsWindowView` ("System Dashboard") is the existing home for exactly this kind of
content: it already renders `percentagePanel`/`capacityPanel`/`temperaturePanel` as
independent panels stacked below `currentReadings`, each panel is just a list of rows, and
it's the one view in this codebase built to show a variable-length collection of readings
rather than a fixed strip. `PeripheralBatteryService` is owned the same way
`BluetoothAudioService` is today — instantiated on `PopoverViewModel` (see
`PopoverViewModel.swift:26`, `let bluetoothAudio = BluetoothAudioService()`) — and
`SystemStatsWindowView` reads it via `viewModel.peripheralBattery` the same way it already
reads `viewModel.systemStats`.

```swift
// PopoverViewModel
let peripheralBattery = PeripheralBatteryService()
```

```swift
// SystemStatsWindowView.body, appended after temperaturePanel
if !viewModel.peripheralBattery.devices.isEmpty {
    peripheralsPanel
}
```

```swift
private var peripheralsPanel: some View {
    FluxaPanelSection(title: "Peripherals", systemImage: "magicmouse") {
        ForEach(viewModel.peripheralBattery.devices) { device in
            HStack {
                Text(device.name)
                Spacer()
                if device.isCharging {
                    Image(systemName: "bolt.fill").foregroundStyle(FluxaTheme.teal)
                }
                Text("\(device.level)%")
                    .monospacedDigit()
            }
        }
    }
}
```

(`FluxaPanelSection` stands in for whatever existing panel-container view
`percentagePanel`/`capacityPanel` already use internally — Codex should match that exact
type rather than introduce a new one; the row content above is the actual specification,
the wrapper is "whatever the other panels use.")

Conditional on `!devices.isEmpty` so an owner with no battery-reporting peripheral paired
sees the dashboard exactly as it looks today — no empty "Peripherals" panel, no
`unavailableNote`-style placeholder row. This is different from every `SystemMetricID`
case, which always has a Customize entry even when unavailable on the current Mac, because
peripherals aren't a fixed catalog — there's no fixed "Peripherals" concept to explain as
unavailable, only a variable set of devices that either exist right now or don't.

`peripheralBattery.refresh()` is called from the same `onAppear`/`onDisappear` pair
`SystemStatsWindowView` already uses for `stats.setDashboardVisible`, so opening the
dashboard forces an immediate refresh rather than waiting up to 60 seconds for the
background timer.

No Customize entry, no menu-bar chip, no popover-strip row for this ticket — the dashboard
panel is the minimum that satisfies "the owner can see it," and extending peripheral
battery to the other surfaces `SystemMetricID` readings already reach is a reasonable
follow-up, not a requirement here.

## Acceptance

1. `PeripheralBatteryReading` and `PeripheralBatterySampler` exist in
   `Sources/FluxaCore/Services/`, `package`-visible, independent of `SystemStatsSampler`.
2. `PeripheralBatterySampler.sample()` excludes the internal battery by
   `kIOPSTransportTypeKey != kIOPSInternalType`, not by list position.
3. A source with no usable `kIOPSCurrentCapacityKey` is omitted entirely — never
   represented as a reading with `level: 0`.
4. `PeripheralBatteryService` exists in `Sources/Fluxa/Services/`, `@MainActor`,
   `@Observable`, exposing `devices: [PeripheralBatteryReading]`.
5. A device absent for exactly one refresh does not disappear from `devices`; absent for
   two consecutive refreshes, it does.
6. Refresh runs independently of `SystemStatsInterval`, on its own fixed ~60s cadence plus
   an on-open trigger.
7. A "Peripherals" panel appears in `SystemStatsWindowView` (System Dashboard) only when
   `devices` is non-empty, listing each device's name and `"\(level)%"`, with a charging
   glyph when `isCharging`. Opening the dashboard triggers an immediate refresh rather than
   waiting for the background timer.
8. `swift test`, `swift build`, `./build.sh` pass; no new strict-concurrency warnings; no
   `public` in `FluxaCore`.
9. Local build launched per `docs/agents/roles.md` — owner can pair a Magic
   Mouse/Keyboard/Trackpad (or borrow one), open the System Dashboard, and see a real
   battery percentage; unplugging it removes the row within two refresh cycles, not
   immediately and not never.

## Out of scope

AirPods and Bluetooth audio-device battery (Q3 — no public API found; `needs-info` if the
owner wants it pursued further). A Customize section to choose which peripherals appear
(Q5 — the list is unfiltered, matching `BluetoothAudioService`'s existing posture). Any
surface beyond the System Dashboard panel decided in Q6 — a popover-strip row, a menu-bar
chip, or a Customize toggle for peripheral battery specifically are reasonable follow-ups,
not required here.

## Risks

- **`06`'s `sources.first` assumption.** `BatterySampler` (already shipped,
  `ready-for-handoff`) picks the internal battery by taking the first entry in
  `IOPSCopyPowerSourcesList`, not by filtering on `kIOPSTransportTypeKey`. In practice the
  internal battery is reliably first on every Mac tested during `06`'s validation, and nothing
  here requires changing already-shipped code. But it's an ordering assumption IOKit's
  documentation does not guarantee, and this ticket's own sampler deliberately does not
  repeat it (Q2). If Antigravity's manual testing of `07` — which necessarily exercises a
  Mac with a peripheral battery paired — ever shows `06`'s reading swap with a peripheral's,
  that's the confirming signal to file `06`'s `sources.first` as its own fast-follow fix,
  not a reason to hold up this ticket.
- **Third-party Bluetooth HID coverage is a hardware-dependent unknown.** Apple's own Magic
  accessories are the confirmed case; whether a given third-party mouse/keyboard implements
  the standard Bluetooth LE Battery Service (and therefore shows up the same way) varies by
  vendor and firmware. This ticket's acceptance criteria are about Apple's own peripherals;
  third-party coverage is a bonus, not a requirement, and Antigravity shouldn't treat a
  missing third-party device as a validation failure — note it in `## Comments` instead.
- **`kIOPSHardwareSerialNumberKey` may not be present on every entry.** The `id` falls back
  to `name` when it's missing, which means two identically-named peripherals of the same
  model paired simultaneously would collide and be treated as one device in
  `missingStreak`/`devices`. Rare (most owners have one Magic Trackpad, not two), and a
  fallback identity collision degrading to "shows one of them" is an acceptable failure
  mode here — not worth a synthetic composite key for a case this narrow.
