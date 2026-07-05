<p align="center">
  <img src="DayBar/Assets.xcassets/AppIcon.appiconset/icon_256.png" alt="DayBar app icon" width="128" height="128">
</p>

<h1 align="center">DayBar</h1>

<p align="center">
  A native macOS <strong>menu-bar app to plan your day, focus with a Pomodoro, and actually finish
  what you planned</strong> — with unfinished tasks carried into tomorrow under a <em>gentle</em>, escalating
  nudge instead of silently disappearing.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-5%20mode%20·%206%20toolchain-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
</p>

<p align="center">
  Lives in your menu bar — no Dock icon. Plan in the morning, work through the day, and run a
  quick end-of-day review before you sleep.
</p>

## Features

- **Daily habits** — recurring rituals (e.g. after morning coffee) on a schedule (every day, weekdays,
  weekends, or custom days); one-tap check-off, streak tracking with a gentle grace day, optional anchor
  reminders, and optional sync to Apple Reminders as recurring reminders.
- **Daily todos** — capture today's plan; check off, delay, reschedule, or drop. Quick-add for **today
  or tomorrow** with a segmented picker.
- **Gentle carry-over** — unfinished tasks roll to the next day and age (grey → amber pill +
  a quiet menu-bar count). Calm by default, never a wall of red.
- **Pomodoro** — customizable focus/break durations, cycles, auto-start; a **live mm:ss
  countdown right in the menu bar**; accurate across sleep/wake (wall-clock based). Optionally
  **skip a break** if you've stepped away long enough (assumes you already rested).
- **Lofi Radio** — built-in **SomaFM** ambient/lofi stations in the panel footer; tap ▶ to start
  (random station) or pick from a simple list; skip stations, now-playing label, offline channel cache;
  menu-bar waveform while playing; **auto-pauses when a focus session ends**.
- **Task history** — browse completed tasks grouped by day (last 30 days).
- **Analytics (Swift Charts)** — tasks and habits tabs; daily / weekly / monthly trends,
  habit consistency heatmap (28 days), streak leaderboard, focus minutes, and Pomodoro sessions.
- **Notifications** — morning planning + evening review reminders, a phase-end alert (shows
  even when the panel is closed), and a once-daily nudge when tasks pile up.
- **End-of-day review** — "Did you finish what you planned?" — triage what's left and jot a
  one-line reflection.
- **Quick-add hotkey** — a global shortcut (default ⌥⌘D) opens the panel focused on the field.
- **Apple Reminders sync** — optional two-way sync with selected Reminder lists (complete,
  delay, and reschedule flow back to Reminders). Habits can sync as recurring reminders on their schedule.
- **Local & private** — stored on-device with SwiftData; no account, no cloud. Radio metadata and
  artwork are cached locally; streams come from [SomaFM](https://somafm.com).

## Requirements

- macOS 15+ (developed on macOS 26 Tahoe)
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build & run

The Xcode project is generated from `project.yml` (it isn't committed):

```sh
xcodegen generate
open DayBar.xcodeproj      # Run the "DayBar" scheme
# or, from the CLI:
xcodebuild -project DayBar.xcodeproj -scheme DayBar -destination 'platform=macOS' build
```

DayBar is an *accessory* app — look for its icon in the **menu bar**, not the Dock.

> For notifications and launch-at-login, run once from Xcode with automatic signing (a free
> Apple ID) so macOS grants permission — the default ad-hoc signing is unreliable for those.

## Test

```sh
xcodebuild -project DayBar.xcodeproj -scheme DayBar -destination 'platform=macOS' test
```

## Architecture

| Target | What |
|---|---|
| `DayBarCore` | Models (`@Model`), `DataStore` (SwiftData), `RolloverEngine`, `EscalationModel`, `PomodoroEngine`, `SomaFMService` / `RadioPlayerManager`, `Analytics`, `NotificationScheduler`, `AppState`. UI-free, unit-tested. |
| `DayBar` | SwiftUI + AppKit menu-bar UI: `NSStatusItem` + borderless `NSPanel` hosting `TodayView`, plus Settings / Analytics / Review / History sheets and the inline `LofiRadioStrip`. |
| `DayBarTests` | XCTest. |

A single `@Observable @MainActor AppState` is the source of truth (read via `@Environment`).
Carry-over age is computed from each task's immutable original planned date; new-day rollover
is idempotent and survives the Mac sleeping; the Pomodoro's truth is a wall-clock `endDate`.

## Roadmap

- **P3b** — Apple Calendar read-mostly integration behind the same adapter protocol.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome.

## License

[MIT](LICENSE) © 2026 Yusril Izza
