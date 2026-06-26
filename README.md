# DayBar

A native macOS **menu-bar app to plan your day, focus with a Pomodoro, and actually finish
what you planned** — with unfinished tasks carried into tomorrow under a *gentle*, escalating
nudge instead of silently disappearing.

![platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![swift](https://img.shields.io/badge/Swift-5%20mode%20·%206%20toolchain-orange)
![license](https://img.shields.io/badge/license-MIT-green)

> Lives in your menu bar — no Dock icon. Plan in the morning, work through the day, and run a
> quick end-of-day review before you sleep.

## Features

- **Daily todos** — capture today's plan; check off, delay, reschedule, or drop.
- **Gentle carry-over** — unfinished tasks roll to the next day and age (grey → amber pill +
  a quiet menu-bar count). Calm by default, never a wall of red.
- **Pomodoro** — customizable focus/break durations, cycles, auto-start; a **live mm:ss
  countdown right in the menu bar**; accurate across sleep/wake (wall-clock based).
- **Analytics (Swift Charts)** — daily / weekly / monthly planned-vs-completed, completion-rate
  trend, focus minutes, and **Pomodoro sessions** (count + average).
- **Notifications** — morning planning + evening review reminders, a phase-end alert (shows
  even when the panel is closed), and a once-daily nudge when tasks pile up.
- **End-of-day review** — "Did you finish what you planned?" — triage what's left and jot a
  one-line reflection.
- **Quick-add hotkey** — a global shortcut (default ⌥⌘D) opens the panel focused on the field.
- **Local & private** — stored on-device with SwiftData; no account, no cloud.

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
| `DayBarCore` | Models (`@Model`), `DataStore` (SwiftData), `RolloverEngine`, `EscalationModel`, `PomodoroEngine`, `Analytics`, `NotificationScheduler`, `AppState`. UI-free, unit-tested. |
| `DayBar` | SwiftUI + AppKit menu-bar UI: `NSStatusItem` + borderless `NSPanel` hosting `TodayView`, plus Settings / Analytics / Review sheets. |
| `DayBarTests` | XCTest. |

A single `@Observable @MainActor AppState` is the source of truth (read via `@Environment`).
Carry-over age is computed from each task's immutable original planned date; new-day rollover
is idempotent and survives the Mac sleeping; the Pomodoro's truth is a wall-clock `endDate`.

## Roadmap

- **P3** — Apple Reminders + Calendar (EventKit) integration behind an adapter protocol.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome.

## License

[MIT](LICENSE) © 2026 Yusril Izza
