# Contributing to DayBar

Thanks for your interest! DayBar is a small, native macOS menu-bar productivity app. This
guide gets you building and explains the conventions.

## Setup

Requirements: **macOS 15+**, **Xcode 26+**, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
git clone git@github.com:underworld14/daybar.git
cd daybar
xcodegen generate          # creates DayBar.xcodeproj from project.yml (not committed)
open DayBar.xcodeproj      # then Run / ⌘U, or use xcodebuild below
```

The `.xcodeproj` is generated and **gitignored** — `project.yml` is the source of truth.
**Re-run `xcodegen generate` whenever you add, remove, or rename a source file**, otherwise the
new file won't be in the build.

## Build & test (CLI)

```sh
xcodebuild -project DayBar.xcodeproj -scheme DayBar -destination 'platform=macOS' build
xcodebuild -project DayBar.xcodeproj -scheme DayBar -destination 'platform=macOS' test
```

Please keep the test suite green and add tests for new logic (the engines, rollover,
analytics, and persistence are all unit-tested under `Tests/DayBarTests`).

## Project layout

| Target | What |
|---|---|
| `DayBarCore` (framework) | Models (`@Model`), `DataStore` (SwiftData), `RolloverEngine`, `EscalationModel`, `PomodoroEngine`, `Analytics`, `NotificationScheduler`, `AppState`. UI-free and unit-tested. |
| `DayBar` (app) | SwiftUI + AppKit: `MenuBarController` (NSStatusItem + NSPanel), `TodayView`, `SettingsView`, `AnalyticsView`, `EndOfDayReviewView`. |
| `DayBarTests` | XCTest. |

## Conventions

- **One source of truth:** a single `@Observable @MainActor AppState`, read by views via
  `@Environment`. Don't reintroduce `ObservableObject`, and don't pass `AppState` by init
  parameter into the menu-bar panel (SwiftUI won't re-render it reliably there).
- **Persistence:** the `*Raw` fields on `@Model` types are the stored source of truth; expose
  typed enums as computed accessors (never store both). Every stored property has a default or
  is optional (lightweight migration).
- **Time is injected:** pass `Date`/`Calendar` into logic (`DayMath`, rollover, analytics,
  Pomodoro) so it's testable and DST/timezone-safe. Avoid reading `Date.now` deep in logic.
- **Menu-bar surface** is AppKit (`NSStatusItem` + a borderless `NSPanel` hosting SwiftUI),
  not `MenuBarExtra` — keep AppKit touchpoints in `MenuBarController`/`AppKitBridge`.
- No force-unwraps in non-test code.

## Signing note

Notifications and launch-at-login need a properly signed bundle. The default build uses local
ad-hoc signing ("Sign to Run Locally"), which is flaky for those features — **run once from
Xcode with automatic signing** (a free Apple ID team) to grant notification permission.

## Pull requests

- Branch off `main`; keep PRs focused.
- Imperative commit subjects ("Add focus-streak stat", not "added").
- Describe what changed and how you verified it (build + tests, and any manual runtime check).
