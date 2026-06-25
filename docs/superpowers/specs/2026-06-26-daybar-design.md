# DayBar — Native macOS Menu Bar Productivity App (Design Spec)

> Approved design. Source of truth for implementation. Phased MVP-first.

## Context

DayBar supports a daily ritual: **plan today's tasks each morning, work through them with a Pomodoro, and before sleep see whether you did what you planned** — unfinished items carry forward as tomorrow's priorities under a *gentle, escalating* nudge so neglected tasks don't silently vanish. Secondary: concise daily/weekly/monthly analytics, and (later) Apple Reminders & Calendar integration.

A 6-agent research+critique workflow validated the macOS stack against Apple docs and community sources and corrected several first-draft traps (mixed observation systems, rollover key in UserDefaults, a contradictory AppKit badge, an unreliable closed-state live countdown, the brittle Settings activation dance, an over-loud escalation that could backfire).

### Locked decisions
- **Native**, accessory menu bar app (no Dock icon). Target **macOS 15+**, develop on 26 (Tahoe).
- **SwiftUI + SwiftData**, single local user.
- **MVP-first**, phased (P1 → P2 → P3).
- **Escalation:** gentle by default (grey→amber, no red alarm); intensity adjustable in Settings.
- **Storage:** local SwiftData + one-tap JSON export/backup. CloudKit deferred.
- **EventKit** (Reminders/Calendar) deferred to **Phase 3** behind an adapter protocol.

## Build tooling (decision)

Full Xcode is **not installed** (active dir = Command Line Tools); `xcodebuild` cannot build a `.xcodeproj`. However the macOS 26 SDK, `swiftc`/`swift build`, `codesign`, and `brew` are present.

**Decision:** ship DayBar as a **Swift Package** (`Package.swift`), buildable today with Command Line Tools:
- `swift build` / `swift run` to develop. Accessory mode is set in code via `NSApp.setActivationPolicy(.accessory)` (no Info.plist required to hide the Dock icon).
- `Scripts/make_app.sh` wraps the built binary into a signed `DayBar.app` (Info.plist w/ `LSUIElement`, ad-hoc `codesign`) — needed only for P2 (notifications, launch-at-login).
- The package opens natively in Xcode; migrating to a dedicated Xcode app target later reuses the same Swift sources unchanged.

Rationale: P1 needs no entitlements/notifications, so SwiftPM unblocks immediate, real progress while preserving the Xcode path. This adapts the original "real Xcode project" decision to the actual environment.

## Architecture

Single source of truth: **`AppState` as `@Observable @MainActor final class`** injected via `.environment`. One observation system only — do **not** mix `ObservableObject` + `@Observable` (nesting an `@Observable` engine inside an `ObservableObject` parent fails to republish).

| Module | Purpose |
|---|---|
| `DayBarApp` (AppShell) | SwiftUI `App` entry. Scene order **hidden `Window` → `MenuBarExtra` → `Settings`**; installs shared `ModelContainer`; sets `.accessory`. No business logic. |
| `DataStore` | Owns `ModelContainer`/`mainContext`; typed fetch helpers from **injected start-of-day `Date`s** (never `Calendar` calls or `@State` inside `#Predicate`); `fetchCount`; centralizes explicit `save()`. |
| `AppState` | `@Observable @MainActor` source of truth. Publishes `overdueCount`, `worstTier`, `isPanelPresented`; owns `PomodoroEngine`; intents (`addTodo`, `toggleComplete`, `delay`, `drop`, `reschedule`). |
| `RolloverEngine` | Idempotent `performRolloverIfNeeded()` keyed on a `lastProcessedDay` stored **inside SwiftData** (same transaction as carry-over mutations). Marks past-due incomplete todos `carriedOver`. Safe to call from 4 triggers. |
| `EscalationModel` | Pure value logic: `carryOverAgeInDays` → tier → visual treatment. Fully unit-testable. |
| `PomodoroEngine` | `@Observable @MainActor`. Wall-clock `endDate` is truth; 1s `Timer` only redraws; phase enum + cycle counter; config from `@AppStorage`; retained `beginActivity` token while running; sleep/wake recompute via **`NSWorkspace.shared.notificationCenter`**. |
| `MenuBarScene` | Nested `Scene` struct holding `AppState`. `MenuBarExtra(.menuBarExtraStyle(.window))` + `MenuBarExtraAccess` (isPresented binding & window introspection for focus). Dynamic label: focus glyph + coarse minutes + overdue badge rendered **inside the SwiftUI label closure**. |
| `TodayView` | Panel UI: today's list w/ checkboxes; **multi-add quick-add** TextField; delay/drop; age pills; Pomodoro strip (live `Text(timerInterval:)` here); `X/Y done`; links to Settings/Analytics. |
| `AppKitBridge` | Isolates AppKit: activation policy, `NSApp.activate`, sleep/wake observers, `openSystemSettingsLoginItems`. Seam for an `NSStatusItem + NSPanel` fallback. |
| `AnalyticsView` (P2) | Swift Charts over plain fetch+reduce first; `DailyStat` pre-aggregate only if proven slow. |
| `NotificationScheduler` (P2) | Wraps `UNUserNotificationCenter`. |
| `SettingsView` (P2) | Hosted **inside the panel** (sheet/tab) to avoid the activation-policy dance. |
| `ExternalSourceProvider` + adapters (P3) | Protocol boundary; `RemindersAdapter` (two-way), read-mostly `CalendarAdapter`. |

## Data model (SwiftData)

**`DailyTodo` (@Model)** — every field defaulted/optional (lightweight-migration-safe):
- `id: UUID` `@Attribute(.unique)`; `title: String = ""`; `notes: String = ""`; `createdDate: Date = .now`
- `plannedForDate: Date` — **normalized `Calendar.startOfDay`**; drives today/overdue queries; mutated on reschedule
- `originalPlannedDate: Date` — normalized start-of-day, **set once, never mutated**; basis for computed age
- `dueDate: Date?`; `completedDate: Date?` (nil == not done)
- `statusRaw: String` — store **only** the raw value; computed `status: TodoStatus` accessor (never persist both). Values: `planned, completed, carriedOver, snoozed, dropped`
- `priorityRaw: Int` (low=0/med=1/high=2); `delayCount: Int = 0`; `snoozedUntil: Date?`; `pomodoroCount: Int = 0`
- `sourceRaw: String = "local"`; `externalIdentifier: String?` (P3)
- **computed (not stored):** `carryOverAgeInDays`, `escalationTier`

**`AppMeta` (@Model)** — single row holding `lastProcessedDay: Date` (rollover idempotency key, atomic with mutations).

**`DailyStat` (@Model, P2, optional)** — `date` (unique, start-of-day), `plannedCount`, `completedCount`, `carriedOverCount`, `focusMinutes`.

**Preferences** via `@AppStorage`: pomodoro durations/cycles/autoStart/sound, `morningReminderTime`/`eveningReviewTime`, escalation `intensity` + thresholds. Launch-at-login read from `SMAppService.mainApp.status`.

## Carry-over escalation (core mechanic)

`age = carryOverAgeInDays` = `Calendar.dateComponents([.day], from: originalPlannedDate, to: startOfDay(now))`, local timezone, compared via `startOfDay` values (DST/timezone-safe; tested across DST + timezone change). Immutable `originalPlannedDate` ⇒ age escalates with **zero daily per-row writes**.

**Gentle default:**
- On-plan (0): neutral, no badge.
- Slipped (1–2d): grey age pill (`1d`), no badge; tooltip "Carried from yesterday."
- Aging (3d+): amber pill (`3d`) + subtle icon; counts toward badge.
- Menu-bar badge: amber count of items age ≥ 3d, suppressed at 0. **No red / row-wash / forced top-sort** by default.
- Adjustable intensity in Settings (ships calm).

Every aging item offers one-tap **Reschedule** and **Drop**; copy frames the next action, never failure.

## Pomodoro

`endDate` (wall-clock) is truth; remaining = `endDate.timeIntervalSinceNow` clamped ≥ 0. 1s `Timer` (`RunLoop .common`, `tolerance ≈ 0.15`) only redraws. Customizable durations/cycles/auto-start. App Nap suppressed only while running via a retained `beginActivity` token. Sleep/wake: observe `NSWorkspace.shared.notificationCenter`; on wake recompute and **fire any missed phase transition immediately**. Closed menu-bar label: static focus glyph + coarse minutes (~30–60s cadence), not a per-second countdown; live countdown is in the open panel.

## Phases

- **P1 — Core MVP:** accessory shell; SwiftData model + `DataStore`; `MenuBarExtra(.window)` + nested Scene + `MenuBarExtraAccess`; `TodayView` (multi-add quick-add, check, delay, drop); gentle carry-over + `RolloverEngine` + `EscalationModel`; `PomodoroEngine` (sleep/wake correct); in-panel basic settings (durations).
- **P2 — Loop & polish:** Swift Charts analytics; `NotificationScheduler`; launch-at-login (`SMAppService`); end-of-day review sheet; full Settings; JSON export; optional global hotkey (`KeyboardShortcuts`).
- **P3 — EventKit:** `ExternalSourceProvider`; `RemindersAdapter` (two-way, `externalIdentifier` dedup, `EKEventStoreChanged` reconciliation); read-mostly `CalendarAdapter`; per-source settings.

## Verification

- Menu-bar surface: launches w/ no Dock/Cmd-Tab entry; panel opens & auto-dismisses; adding a todo re-renders live.
- Quick-add multi-add: Enter adds + clears + keeps panel open & focus; Escape/outside-click dismisses; persists across relaunch.
- Check/delay/drop: toggle sets `completedDate`; delay increments `delayCount`; drop sets status.
- Rollover (date simulation): advance system date 1 day → `carriedOver` exactly once; multi-day → catch-up; same-day relaunch → idempotent.
- Escalation tiers: offsets 0/1/3 days → grey/amber pills + amber badge counting age≥3d, gone at 0.
- Pomodoro sleep/wake: `pmset sleepnow` past phase end → remaining recomputed from `endDate`, missed transition fires on wake.
- Unit tests: `EscalationModel` tier boundaries; `RolloverEngine` idempotency & multi-day catch-up; age across DST + timezone change.

## Risks & mitigations
- MenuBarExtra fragility → nested-Scene + `@Observable` + `MenuBarExtraAccess`; multi-add reduces dismiss reliance; `AppKitBridge` is the `NSPanel` fallback seam.
- TextField focus in non-activating panel → `activate` + `makeKey()` + `@FocusState`; verify early.
- Rollover across sleep → idempotent, SwiftData-keyed `lastProcessedDay`, 4 triggers, multi-day catch-up tested.
- Notifications need a signed bundled `.app` (P2) → validate signing identity early in P2.
- SwiftData → explicit `save()`; lightweight-migration-only accepted (every field defaulted/optional).
