# 14 — Per-app volume mixer

Status: wontfix
Owner: claude
Type: task
Spec: —
Blocked by: —
Source: clean-room. Feature idea only. No upstream code read.

## Question

Extend the existing `audioOutput` action: a button that opens a small mixer panel listing
every app currently producing audio, each with its own volume slider — a Windows-style
per-app mixer, which macOS has no built-in equivalent of.

Decide:

- **Whether this is buildable at all without a virtual audio driver.** This is the load-
  bearing question and needs to be answered before anything else in this ticket. CoreAudio's
  public HAL API (what `AudioOutputService` already uses) controls *devices*, not individual
  app streams — there is no public, writable "set this app's output volume" property. Every
  mixer app that does this on macOS (Background Music, eqMac, Loopback-based setups) works by
  installing a **virtual audio device** (a CoreAudio driver, either an `AudioServerPlugIn` or
  a kernel extension depending on age), setting it as the system default output, and routing
  each process's audio through it internally — the driver is the mixer, not a property on the
  real device. That's a fundamentally different scope than every other action in Fluxa: a
  signed, notarized system audio driver, its own install/uninstall flow, and (depending on the
  approach) a privileged helper, versus everything else in this app being a thin AppKit/
  CoreAudio HAL wrapper with no privileged components at all.
  - macOS 14.2's Core Audio "process tap" API (`AudioHardwareCreateProcessTap`,
    `kAudioHardwarePropertyProcessObjectList`, per-process `AudioObjectID`s) is real and
    public, but as far as I can tell it's a **capture** API — built for recording/monitoring
    a process's audio output (screen recorders use it to capture app audio), not a **write**
    path for setting that process's playback volume. If a public writable per-process volume
    property does exist somewhere in that API, that changes this ticket entirely — this needs
    to be confirmed against current API docs before promising a design, not assumed either
    way from memory.
- If a driver turns out to be required: is that acceptable for Fluxa? The project's own
  `map.md` already rejected fan control for needing "a privileged root helper," on the same
  kind of grounds. A virtual audio driver is a smaller ask than SMC writes, but it's still a
  system-level install with its own signing/notarization/entitlement story, a possible
  System Settings → Privacy approval step, and real risk of routing bugs (silence, wrong
  device, or every app's audio going to the wrong output) that this project has not had to
  deal with anywhere else yet.
- If some scoped-down version turns out feasible without a driver — e.g. only the apps that
  themselves expose a controllable audio-unit volume, or only reading (not setting) a
  per-app level via the process-tap API — is that degraded feature still worth having, or is
  "full Windows-style mixer or nothing" the actual ask?

## Notes

I don't want to write a spec that assumes an API I'm not certain exists. Before this can move
to `spec-pending` → an actual design, I need to confirm one way or the other whether macOS
exposes any public, writable per-process volume control today. If it doesn't (which is my
current best understanding), the honest options are: build the virtual-driver version (a much
bigger ticket than anything else in this group, worth scoping separately if you want it), or
park this in the same bucket as fan control — a real feature, rejected on cost/risk grounds
for this app.

## Answer

**Confirmed: no public writable per-process volume API exists.** Checked directly against
the current CoreAudio headers shipped in Xcode's macOS SDK
(`CoreAudio.framework/Headers/AudioHardware.h`, `AudioHardwareTapping.h`), not from memory:

- The `Process` class (`kAudioProcessClassID`) exposes exactly five properties:
  `kAudioProcessPropertyPID`, `...BundleID`, `...Devices`, `...IsRunning`,
  `...IsRunningInput/Output`. No volume, no gain, nothing writable that affects playback level.
- `kAudioDevicePropertyProcessMute` exists on `AudioDevice`, but it's mute-only (no continuous
  level), it only affects **the current process's own** audio ("the current process's audio
  will be zeroed out"), and it explicitly does not apply to aggregate devices. It cannot be
  used to mute or attenuate a different app.
- `AudioHardwareCreateProcessTap` / `AudioHardwareDestroyProcessTap` (macOS 14.2+,
  `AudioHardwareTapping.h`) create a **Tap** object whose doc comment describes it as
  something that "contains a list of input streams that originate from the output stream(s)
  of one or more processes" — a capture/monitoring construct, with no write-side property for
  altering what the tapped process actually plays.

So the original assumption was right: there is no HAL property anywhere that lets one process
set another process's playback volume. A per-app mixer on macOS is only achievable by becoming
the system's default output device (a virtual audio driver) and mixing internally — not
something addable as a small extension of `AudioOutputService`.

Given that, and that this project has already drawn the line at privileged/system-level
components (fan control rejected in `map.md` on the same grounds), this ticket is parked
rather than spec'd: `wontfix`, unless the owner explicitly wants to scope the virtual-driver
version as its own, much larger effort.

## Comments

- 2026-09-01, claude: ticket opened at the owner's request (extends `audioOutput` with a
  per-app mixer panel). Flagged as feasibility-uncertain rather than writing a spec straight
  away: everything else in this effort has been a thin wrapper over a known public API, and
  I'm not confident a public writable per-app volume control exists on macOS at all — every
  mixer app I know of achieves this via a virtual audio driver, not a HAL property. Left the
  Answer open rather than guessing; needs a decision on whether to pursue the driver route,
  a degraded no-driver version, or shelve it.
- 2026-09-01, claude: verified against the actual CoreAudio headers in the installed Xcode
  SDK rather than relying on recollection. The `Process` class has no volume-related property
  at all; the closest thing (`kAudioDevicePropertyProcessMute`) only mutes the *current*
  process, not a target one; the macOS 14.2 process-tap API is confirmed capture-only, no
  write path. No public per-process volume control exists. Status set to `wontfix` pending
  the owner's call on whether to pursue a virtual-driver version as separate, larger scope.
