# Fluxa – Phase 1 (MVP)

## Goal
Build a minimal, production-ready macOS menu bar app that provides fast access to essential workspace controls.

The app must be stable, clean, and App Store-oriented.
No fake features. Only real, reliable functionality.

---

## Core Features

- Hide Desktop Icons
- Screen Clean (fullscreen black overlay, exit on ESC/click)
- Focus Mode (open system settings or best fallback)
- Audio Output Switch (list and switch devices)
- Lock Keyboard (safe fallback only, no unsafe hacks)
- Microphone Mute / Unmute (toggle using input volume control via CoreAudio)
Microphone feature requirements:
- Detect current input device
- Read current input volume
- Set input volume to 0 when muting
- Restore previous volume when unmuting
- Handle device changes gracefully
- If control is not possible, provide a clear fallback or disabled state

---

## Product Principles

- Minimal and fast
- No broken or fake toggles
- Clear feedback for every action
- Honest handling of system limitations
- Native macOS feel

---

## UI Structure

- Menu bar app with popover
- Section: Favorites (optional)
- Section: Main features list
- Footer:
  - Customize
  - Quit

---

## Technical Requirements

- Swift + SwiftUI
- Clean architecture (no monolithic views)
- Separate:
  - Models
  - ViewModels
  - Services
- Feature-based structure

---

## Feature Types

Each feature must be implemented as one of:
- Toggle (true/false state)
- Action (one-shot)
- Submenu (e.g. audio output)

---

## Required System Behaviors

- Global shortcut to open Fluxa
- Launch at login support
- Persistent user settings
- Safe permission handling

---

## Constraints

- Prefer public macOS APIs
- No fake implementations
- No unsafe hacks for keyboard locking
- If a feature is limited, show correct UX fallback

---

## Expected Result

A stable MVP version of Fluxa that:
- compiles and runs
- provides real working features
- has clean UI and UX
- is ready for further expansion in Phase 2

## Design System

The app must follow a clean, native macOS design using SF Symbols.

### Icon Guidelines

- Use SF Symbols only
- Default style: outline icons
- Active state: use filled variants when available
- Keep icon style consistent across all features
- Avoid mixing unrelated visual styles

### Feature Icons

- Hide Desktop Icons:
  - default: `desktopcomputer`
  - active: `desktopcomputer.slash`

- Screen Clean:
  - `sparkles`

- Focus Mode:
  - default: `moon`
  - active: `moon.fill`

- Audio Output:
  - `speaker.wave.2`

- Lock Keyboard:
  - `keyboard`

- Microphone:
  - active: `mic.fill`
  - muted: `mic.slash.fill`

### System Actions (Footer)

- Customize / Settings:
  - `slider.horizontal.3`

- Quit:
  - `power`

### UI Behavior

- Icons should reflect state dynamically
- Active features should be visually distinguishable
- Use system colors (no custom heavy styling)
- Maintain a minimal and elegant look

### Implementation Note

Icons should be centralized in a single mapping system (e.g. enum or helper),
not hardcoded in multiple views.
