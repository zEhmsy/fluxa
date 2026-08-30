# 07 — Peripheral battery levels

Status: spec-pending
Owner: claude
Type: task
Spec: —
Blocked by: 03, 06
Source: clean-room. Feature idea only. No upstream code read.

## Question

Battery for connected peripherals: AirPods, Magic Mouse, Magic Keyboard, Magic Trackpad,
third-party Bluetooth devices.

Fluxa already has `BluetoothAudioService` using IOBluetooth, so the device enumeration
half partly exists — read it before designing, and extend rather than duplicate.

Sources to weigh:

- `IOBluetoothDevice` for classic Bluetooth battery
- IORegistry `BatteryPercent` for HID peripherals (Magic Mouse/Keyboard/Trackpad)
- AirPods report **three** levels — left, right, case — not one

## Notes

Peripheral battery reporting is the flakiest area of this group: devices vanish and
reappear, report stale values while asleep, and some report nothing at all. A device that
reports no battery must be absent from the list, not shown at 0%.

Design the refresh so a disconnected device doesn't churn the popover.

## Answer

_(pending)_

## Comments

_(none)_
