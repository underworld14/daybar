# DayBar

A native macOS **menu bar** productivity app: plan today's tasks each morning, work
through them with a Pomodoro, and before sleep see whether you did what you planned —
with unfinished items carried forward as tomorrow's priorities under a *gentle*,
escalating nudge.

> Status: **Phase 1 (Core MVP) implemented and verified.** See
> `docs/superpowers/specs/2026-06-26-daybar-design.md` for the full design and roadmap.

## Requirements

- macOS 15+ (developed on macOS 26 Tahoe)
- Swift 6.3 toolchain — **Command Line Tools is enough** for Phase 1 (no full Xcode needed yet)

## Run it

```sh
swift run DayBar
```

DayBar is an *accessory* app: it has **no Dock icon**. Look for its item in the **menu
bar** (top-right). Click it to open the panel — add tasks, check them off, delay/drop
them, and start a Pomodoro. Quit from the panel's "Quit" button.

## Verify the logic

There is no GUI test harness on Command Line Tools, so a headless check-runner exercises
the core logic (escalation tiers, DST/timezone-safe day math, idempotent sleep-safe
rollover, AppState intents, Pomodoro wall-clock + sleep catch-up):

```sh
swift run DayBarChecks
```

It prints each check and exits non-zero on any failure.

## Architecture

A SwiftPM package with a testable, UI-free core and a thin SwiftUI executable.

| Target | What |
|---|---|
| `DayBarCore` | Models, `DataStore`, `RolloverEngine`, `EscalationModel`, `PomodoroEngine`, `AppState`, `AppKitBridge` — all UI-free and headless-runnable. |
| `DayBar` | SwiftUI `@main` app: `MenuBarExtra(.window)` + `TodayView`. |
| `DayBarChecks` | Headless assertion runner (stands in for unit tests under CLT). |

Single source of truth: `AppState` (`@Observable @MainActor`). The carry-over age is a
*computed* value from each task's immutable `originalPlannedDate`, so escalation needs no
daily per-row writes. New-day rollover is idempotent and keyed on `lastProcessedDay`
stored alongside the data, so it survives the Mac sleeping across one or many days. The
Pomodoro's truth is a wall-clock `endDate`, so the countdown stays correct across
sleep/wake and fires any missed transition on wake.

## Build tooling note

Phase 1 ships as a **Swift Package** persisting to a local JSON file
(`~/Library/Application Support/DayBar/daybar-store.json`). This is deliberate: full Xcode
isn't installed, and SwiftData's `@Model` macro plugin and XCTest/Testing modules are
Xcode-only — neither is available to `swift build` under Command Line Tools.

When Xcode is installed, migrating the persistence layer to **SwiftData** touches only
`Sources/DayBarCore/Data/DataStore.swift` and the two model files (the public store API is
unchanged). The JSON store also doubles as the "export/backup" format planned for Phase 2.

## Roadmap

- **P2** — Swift Charts analytics (daily/weekly/monthly), notifications (morning plan /
  evening review / Pomodoro phase-end), launch-at-login, end-of-day review, JSON export,
  optional global quick-add hotkey.
- **P3** — Apple Reminders + Calendar (EventKit) behind an adapter protocol.
