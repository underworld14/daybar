# DayBar

A native macOS **menu bar** productivity app: plan today's tasks each morning, work
through them with a Pomodoro, and before sleep see whether you did what you planned —
with unfinished items carried forward as tomorrow's priorities under a *gentle*,
escalating nudge.

> Status: **Phase 1 done. Phase 2 in progress** — now a full Xcode app (SwiftData + XCTest +
> signed `.app`). Foundation landed; the P2 features (analytics, notifications,
> launch-at-login, end-of-day review, full settings, JSON export/import, global hotkey) are
> being layered on. See `docs/superpowers/specs/2026-06-26-daybar-design.md`.

## Requirements

- macOS 15+ (developed on macOS 26 Tahoe), **Xcode 26+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Generate, build, run

The Xcode project is generated from `project.yml` (not committed):

```sh
xcodegen generate          # creates DayBar.xcodeproj
open DayBar.xcodeproj       # then Run the "DayBar" scheme
```

Or from the CLI:

```sh
xcodebuild -project DayBar.xcodeproj -scheme DayBar -destination 'platform=macOS' build
```

DayBar is an *accessory* app — **no Dock icon**. Look for its item in the **menu bar**.

> For notifications and launch-at-login (Phase 2) to work, the app must be a signed bundle.
> The build uses local ad-hoc signing ("Sign to Run Locally"); running once from Xcode with
> automatic signing (your free Apple ID) is the most reliable way to grant notification
> permission.

## Test

```sh
xcodebuild -project DayBar.xcodeproj -scheme DayBar -destination 'platform=macOS' test
```

XCTest target `DayBarTests` covers escalation tiers, DST/timezone day-math, rollover
idempotency/multi-day catch-up, SwiftData persistence, and JSON import/export.

## Architecture

| Target | What |
|---|---|
| `DayBarCore` | Framework: models (`@Model`), `DataStore` (SwiftData), `RolloverEngine`, `EscalationModel`, `PomodoroEngine`, `AppState`, DTOs, `AppKitBridge`. |
| `DayBar` | SwiftUI `@main` app: `MenuBarExtra(.window)` + `TodayView`. |
| `DayBarTests` | XCTest unit tests. |

Single source of truth: `AppState` (`@Observable @MainActor`), read by views via
`@Environment`. Carry-over age is computed from each task's immutable `originalPlannedDate`;
rollover is idempotent and keyed in the SwiftData store; the Pomodoro's truth is a
wall-clock `endDate`. Persistence is **SwiftData**; the Phase-1 `daybar-store.json` is
imported once on first launch and JSON remains the export/backup format.

## Roadmap

- **P2 (in progress)** — analytics (Swift Charts), notifications, launch-at-login,
  end-of-day review, full settings, JSON export/import, global quick-add hotkey.
- **P3** — Apple Reminders + Calendar (EventKit) behind an adapter protocol.
