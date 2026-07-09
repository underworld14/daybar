# DayBar — End-to-End Product & Code Audit

A full pass across all nine subsystems — menu bar shell, Pomodoro, todos & rollover, habits, analytics, end-of-day review & mood, Reminders sync, lofi radio, and settings/persistence. Every candidate bug below was independently re-verified against the actual source before being called "confirmed."

| Metric | Result |
|---|---|
| Tests passing | 167 / 167 |
| Compile errors | 0 |
| Confirmed bugs | 29 |
| UX issues found | 59 |
| Quality improvements | 49 |
| Feature ideas | 41 |
| Subsystems audited | 9 |

**Contents:** [Fix first](#start-here--fix-first) · [Why these keep happening](#why-these-keep-happening) · [Cross-cutting UX](#cross-cutting-ux) · [Feature roadmap](#feature-roadmap) · [Full findings by subsystem](#full-findings-by-subsystem) · [Method](#method)

---

## Start here — fix first

Thirteen findings curated for impact: real data loss, inverted logic, and the two cross-cutting gaps (no undo, no accessibility) that showed up independently in four or more subsystems.

**1. [HIGH · Data loss] Every SwiftData save failure is swallowed silently**  
`DataStore.save()` only `print()`s on failure — the UI keeps showing edits that were never actually written to disk.  
`DataStore.swift:33` · _confirmed by build/verification_

**2. [HIGH · Data loss] Restoring a backup can leave the store empty**  
`importSnapshot()` deletes and commits before re-inserting and committing again — a crash between the two calls leaves no rollback.  
`DataStore.swift:306` · _confirmed by build/verification_

**3. [HIGH · Data loss] Stop discards the whole focus session**  
The Pomodoro Stop button bypasses AppState and never calls `onPhaseEnd`, so unlike Pause+Skip, the elapsed minutes are never recorded to `FocusSession`.  
`PomodoroEngine.swift:122` · _confirmed by build/verification_

**4. [HIGH · Confusing] Finishing a carried-over task makes it disappear, not complete**  
RolloverEngine never advances `plannedForDate`, so a completed carried-over todo satisfies neither the "today" nor the "carried over" query — it vanishes with no checkmark moment.  
`AppState.swift:220` · _confirmed by build/verification_

**5. [HIGH · Inverted logic] "Mark incomplete" on a skipped habit marks it complete**  
Both branches of the menu route through the same `toggleHabit()` call, so a skipped habit can be flipped to *completed* by a button promising the opposite — with no way back to pending.  
`AppState.swift:381` · _confirmed by build/verification_

**6. [HIGH · Data loss] A completed Reminders-synced task can silently desync forever**  
The push queue is in-memory only; quitting before it drains loses the change and nothing ever retries it.  
`RemindersSyncEngine.swift:9` · _confirmed by build/verification_

**7. [HIGH · Sync leak] Turning off Reminders sync for one habit doesn't stop it from being overwritten**  
The per-habit toggle never clears the external link, so a remote edit can silently flip a local habit back on after the user explicitly opted out.  
`HabitRemindersSyncEngine.swift:148` · _confirmed by build/verification_

**8. [HIGH · No safety net] Drop, Archive habit, and Stop are all one click with zero undo**  
Found independently in four different subsystems — each looks destructive, behaves destructively, and offers no confirmation or recovery.  
`cross-cutting` · _cross-subsystem_

**9. [HIGH · Accessibility] Most secondary controls are invisible to VoiceOver and keyboard users**  
Row menus, the weekday picker, every chart, and the Pomodoro transport are hover-only with no accessibility label — the single most repeated gap in the codebase.  
`cross-cutting` · _cross-subsystem_

**10. [MEDIUM · Root cause] The dominant error-handling style is catch-and-print()**  
This one pattern is the underlying mechanism behind most of the data-loss bugs above — failures become invisible instead of recoverable.  
`systemic pattern` · _systemic pattern_

**11. [MEDIUM · Timezone] The app's Calendar is captured once at launch and never refreshed**  
Fly to a new timezone with DayBar still running and every day-boundary calculation keeps using the old offset for the rest of the session.  
`AppState.swift:72` · _confirmed by build/verification_

**12. [MEDIUM · Misleading stat] Analytics' habit "avg/day" is actually avg-per-bucket**  
Switch the Habits tab to Week or Month view and the number silently overstates daily consistency by up to ~7×.  
`AnalyticsView.swift:138` · _confirmed by build/verification_

**13. [MEDIUM · Build-verified] Two Swift 6 warnings will become hard compile errors**  
Found by actually building the project (not by the review agents): a MainActor-isolated `static let` is used as a default-parameter value from a nonisolated context — legal under today's Swift 5 language mode, a compile error the day this project switches on.  
`AppState.swift:637,642` · _verified via xcodebuild (not agent-found)_

---

## Why these keep happening

Seven code-level patterns that recur across unrelated subsystems — each one is a root cause, not a single bug, so fixing the pattern once prevents a whole class of future regressions.

### Errors are swallowed with print()/try? and never surfaced to the user

The dominant error-handling style throughout the codebase is to catch a throwing call, print it to the console, and continue as if it succeeded — with no user-visible signal, retry, or fallback. This turns real failures (disk full, EventKit denial, transient SwiftData fetch errors) into silent, hard-to-diagnose data loss or stale state.

- DataStore.save() (Sources/DayBarCore/Data/DataStore.swift) only print()s on context.save() failure
- RolloverEngine.performRolloverIfNeeded uses try? on store.appMeta()/overdueIncompleteTodos and unconditionally returns true regardless of whether the save actually persisted
- SettingsView's .onChange(of: launchAtLogin) does try? LaunchAtLogin.setEnabled(newValue) and silently reverts the toggle on any thrown SMAppService error
- RemindersSyncEngine/HabitRemindersSyncEngine collapse every failure source (auth, fetch, push, pull) into one shared lastSyncError string with no per-operation detail

### Optimistic local state is stamped before an async operation confirms success, with no durable record of pending work

Several places update in-memory/local state to reflect an outcome (a sync timestamp, a 'day processed' marker, a completed import) before the corresponding write/push has actually been confirmed to persist, and the tracking of 'what's still pending' lives only in RAM. If the process quits or a later step fails, the optimistic state is left inconsistent with reality and nothing ever retries or corrects it.

- RemindersSyncEngine.pushQueue is an in-memory Set<UUID>; AppState.markRemindersTodoLocallyModified stamps todo.externalModifiedAt before the push runs, so quitting before the push loses the change forever and the stale timestamp then suppresses the corrective pull
- RolloverEngine.performRolloverIfNeeded mutates status + lastProcessedDay and calls store.save(), then returns true unconditionally without checking whether the save succeeded
- DataStore.importSnapshot deletes and commits (save()) before re-inserting and committing again (save()) — a crash or failure between the two calls leaves the store fully empty with no rollback

### Row/icon controls are hover-only and lack VoiceOver accessibility labels

The same SwiftUI shape — a secondary action revealed only via .opacity(hovering ? 1 : 0) bound to .onHover, and bare Image(systemName:) buttons with no .accessibilityLabel — recurs almost verbatim across every major view file, leaving keyboard-only and VoiceOver users unable to discover or operate large parts of the app.

- TodayView.swift: TodoRow and HabitRow's '...' action menus and status checkboxes
- EndOfDayReviewView.swift: habit-open and todo-complete toggle icons
- HabitsSettingsSection.swift: the weekday picker's seven identical unlabeled S/M/T/W/T/F/S buttons
- LofiRadioStrip.swift: previous/next/retry buttons (inconsistent with the one Play/Pause button that does have a label)
- AnalyticsView.swift: no chart has an accessibilityChartDescriptor or per-mark label

### Hand-maintained duplicate/mirror logic that must be manually kept in sync with its source of truth, and has already drifted

Multiple places re-derive or re-encode state/logic that already exists canonically elsewhere, using a separate hand-written representation (a second decision tree, a concatenated 'snapshot string', a magic-number layout estimate, a duplicated string literal) instead of referencing the source directly — and in each case the audit found the duplicate had already fallen out of sync.

- DayBarApp.swift's dead MenuBarLabel duplicates MenuBarController.updateStatusItem()'s symbol logic but is missing the radio-playing branch
- MenuBarController.desiredPanelHeight() hand-derives TodayView's real SwiftUI layout in constants and is already missing a section
- SettingsView's notifSnapshot/pomodoroSnapshot interpolated strings must list every relevant @AppStorage key by hand; omitting backlogNotify/phaseEndNotify silently broke their .onChange-triggered rescheduling
- NotificationScheduler.ID.evening is private, so MenuBarController.userNotificationCenter(_:didReceive:) re-hardcodes the literal "evening.review" string to detect the tap

### Meaningful state is encoded as color/opacity alone with no accessible fallback

Several custom SwiftUI drawing views distinguish real, sometimes important states purely through hue or opacity differences on similar colors, with no icon, text label, pattern, or accessibility value attached to the mark.

- TodayView.swift's AgePill: fresh vs. aging conveyed only by gray-vs-orange tint
- HabitHeatmapRow.swift: completed / grace-used / skipped / unscheduled cells differ only by fill-color opacity
- AnalyticsView.swift: all six Swift Charts have no accessibilityLabel/accessibilityValue/accessibilityChartDescriptor

### Calendar.current/Date() is read directly in places that bypass the app's own injected-calendar convention

AppState and DayMath establish an explicit pattern of threading a single injected Calendar/now through call sites for testability and DST/timezone correctness, but several call sites — including one that causes a real user-facing bug — read Calendar.current or Date() directly instead, and AppState's own injected calendar is itself captured once at launch and never refreshed on a system timezone change.

- AppState.calendar (Sources/DayBarCore/State/AppState.swift) is a `let` snapshot of Calendar.current taken at init and never re-fetched on timezone change, with no NSSystemTimeZoneDidChangeNotification observer anywhere in the app
- NotificationScheduler.scheduleHabitAnchors computes 'today' via Calendar.current.startOfDay(for: Date()) instead of using the caller's already-injected now/calendar
- HabitsSettingsSection's HabitEditorSheet.timeBinding calls Calendar.current.date(bySettingHour:...) directly instead of the app's injected calendar

### Fully-built features/fields exist in the model or a lower layer but are never wired to any UI, and have started to bit-rot

Multiple subsystems contain complete, sometimes unit-tested implementations (a cache, a data field, a whole export/import path, an abstraction layer) that no live code path ever calls, which both wastes maintenance surface and signals an intended user-facing feature was never finished.

- Sources/DayBar/DayBarApp.swift's MenuBarLabel and most of Sources/DayBarCore/System/AppKitBridge.swift's helpers are unused (call sites bypass them directly)
- Sources/DayBarCore/Radio/RadioArtworkCache.swift and AppState.artworkData(for:) have no caller in any View
- DailyTodo.snoozedUntil/delayCount/pomodoroCount (Sources/DayBarCore/Model/DailyTodo.swift) are written but never read by any query or view
- EscalationThresholds' doc comment promises a Settings intensity control that doesn't exist (Sources/DayBarCore/Model/EscalationModel.swift)
- DataStore.exportSnapshot()/importSnapshot() (Sources/DayBarCore/Data/DataStore.swift) are unit-tested but have no Settings UI entry point

---

## Cross-cutting UX

The UX issues that would matter most to a daily user, merged across subsystems where the same gap was reported more than once.

- **Destructive actions (Drop, Archive, Stop) have no confirmation or undo** — One-click destructive actions are styled destructively but behave irreversibly with zero safety net: dropping a todo (TodayView, EndOfDayReviewView), archiving a habit (HabitsSettingsSection — with no 'unarchive' path anywhere in the app), and stopping an in-progress Pomodoro session (TodayView, which also silently discards the elapsed focus time from Analytics because stop() never calls onPhaseEnd) are all one tap/click, sitting right next to fully-reversible actions in the same menu, with no confirmation dialog and no visible undo. Users experience mis-clicks as tasks/habits/sessions 'just disappearing.'
- **Most row and icon-only controls are hover-only and unlabeled for VoiceOver** — TodoRow's and HabitRow's '...' action menus, the header settings menu, Pomodoro's play/pause/stop/skip buttons, the End-of-Day Review's habit/todo toggles, several Lofi Radio transport buttons, and every Analytics chart all rely on `.opacity(hovering ? 1 : 0)`/`.onHover` for discoverability and bare SF Symbol images with no `.accessibilityLabel`. There is no keyboard-focus or VoiceOver path to discover or use these controls at all — this is the single most repeated gap across the app's UI code.
- **Automatic background actions happen silently, leaving the user to wonder what happened** — When DayBar acts on the user's behalf, it gives no acknowledgment: idle-break-skip auto-starts the next focus session with zero sound/banner/note, so returning users find a running timer unexplained; habit anchor reminders can fire hours after a habit was already completed (toggleHabit never reschedules notifications) or on days the habit isn't even scheduled (the underlying calendar trigger has no weekday awareness); and the once-daily backlog nudge can silently never fire for an entire day if the first refresh happens after 2pm. Each behavior is individually gentle, but the total absence of any visible trace makes the automation feel unpredictable rather than calm.
- **Completing a carried-over (overdue) task makes it vanish instead of showing it as done** — Because RolloverEngine only changes a carried-over todo's status and never advances its plannedForDate, completing it satisfies neither the 'today' query nor the 'carried over' query — the row disappears from the panel the instant it's checked off, with no checkmark/strikethrough moment, and is only visible again in the separate Task History sheet. A just-finished action looks exactly like a deletion.
- **A completed vs. skipped habit look identical, and 'Mark incomplete' on a skipped habit actually marks it complete** — HabitRow renders any non-completed log — whether truly untouched or explicitly skipped — as the same plain gray circle, so users can't tell what they've already dismissed for the day. Worse, tapping 'Mark incomplete' on a skipped habit routes through the same toggleHabit function used for the normal pending→completed toggle, so it actually sets the habit to completed — the opposite of what the label promises — and there is no UI path back to a pending state.
- **Toggle and status UI can silently lie about whether a feature is actually working** — The 'Sync with Reminders' toggle stays visually ON even when EventKit access is denied and nothing is syncing; 'Launch DayBar at login' silently snaps back off with zero explanation if SMAppService registration throws; and notification-permission, Apple-Intelligence, and login-item status rows in Settings are only refreshed when the sheet first appears, so granting/revoking a permission in System Settings and returning to DayBar leaves a stale row until an unrelated control is toggled.
- **Meaningful state is conveyed by color or opacity alone in several places** — The overdue-task age pill (orange vs. gray), the habit consistency heatmap (subtly different green/gray opacities for completed vs. grace-used vs. skipped), and every Analytics chart (no VoiceOver descriptor at all) communicate real, sometimes important distinctions through hue/opacity only, with no icon, label, or accessibility value — unreadable for colorblind users and invisible to VoiceOver.
- **The floating panel doesn't dismiss when switching apps via keyboard or Mission Control** — The only auto-dismiss mechanism is a global mouse-click monitor; there's no applicationDidResignActive/space-change handling, so Cmd-Tabbing away or entering Mission Control leaves the DayBar panel floating on top of whatever the user switched to — unlike Control Center or Notification Center, which dismiss on app switch.

---

## Feature roadmap

The highest-value ideas, several synthesized from proposals that two or three subsystems independently converged on (see "Full findings by subsystem" below for all 41).

- **A single, calm 'Undo' toast for destructive actions** — Build one small, reusable 'X · Undo' toast component and use it everywhere a destructive-feeling action already exists as a soft-delete under the hood: dropping a todo, archiving a habit, and stopping a Pomodoro session mid-flight. Since drop() and archiveHabitTemplate() are already non-destructive status flips, this is almost entirely a UI change.  
  _Why:_ Directly closes the most repeated, highest-severity UX gap found across four subsystems (App Shell, Daily Todos, Habits, Pomodoro) with one small piece of shared infrastructure rather than four one-off fixes, and a toast fits the calm philosophy better than a modal confirmation would.
- **Wire up the existing backup/restore machinery and add a quiet 'last saved' status line** — DataStore.exportSnapshot()/importSnapshot() are already implemented and unit-tested but have no Settings entry point. Add a 'Back up to file / Restore from file' pair (with a confirmation step before the destructive import), paired with a small factual status line in Settings ('Local data last saved HH:mm') sourced from a new lightweight save-success signal instead of DataStore.save()'s current print-only failure path.  
  _Why:_ Gives local-first, no-cloud users a real safety net using infrastructure that's already built, and directly mitigates the systemic silent-save-failure pattern found across Persistence, Rollover, and Reminders sync — turning an invisible risk into a small, reassuring, non-alarming status readout.
- **A real quiet-acknowledgment channel for automatic actions, generalized from the existing ad-hoc banner** — AppState already reuses one habitMilestoneMessage string as a catch-all ephemeral banner for both habit-streak milestones and 'Focus ended — music paused.' Formalize that into a proper small queue of short, dismissible, non-modal banners, and use it to acknowledge every silent automatic action found in this audit: idle-triggered break skip, habit-anchor rescheduling after a task is completed, and pending Reminders sync changes.  
  _Why:_ One piece of shared infrastructure closes several independently-reported 'the app did something and told me nothing' gaps (App Shell, Pomodoro, Habits, Reminders) — a need only visible from the cross-subsystem view, since each subsystem proposed its own disconnected one-off banner.
- **A unified 'Away / Paused' mode spanning habits, todos, and charts** — Merge the independently-proposed per-subsystem ideas — habit vacation-pause, a todo 'Someday' shelf, and chart 'away' bands — into one coherent concept: a date range the user marks as away, which HabitEngine excludes from materialization/streak-breaking, escalation/rollover excludes from aging, and Analytics renders as a neutral gray band instead of a gap or a zero.  
  _Why:_ Three subsystems each proposed a fragment of this same idea in isolation; unifying it into one data concept is more coherent for the user and cheaper to build than three separate features, and it reinforces the app's explicit 'gentle, never a wall of red' philosophy for real-life interruptions.
- **One calm weekly digest instead of four separate periodic nudges** — Combine the separately-proposed 'weekly habit summary,' 'weekly backlog check-in,' and 'weekly mood recap' into a single once-a-week panel card or notification built entirely from already-computed local aggregates (HabitAnalytics, backlog aging, MoodAnalytics, FocusSession counts) — one quiet moment of reflection instead of multiple disconnected pings.  
  _Why:_ A cross-cutting view surfaces an opportunity the per-subsystem audits missed individually: three subsystems each want a weekly check-in, and shipping them separately would mean three new notification types where one integrated, low-frequency digest better serves the calm/no-nag philosophy.
- **Unarchive a habit** — Add a lightweight 'Archived habits' list (in Settings or Analytics) with a 'Restore' action that flips isActive back to true.  
  _Why:_ Directly closes a confirmed irreversibility gap using data that's already retained for analytics — no new infrastructure, low risk, high value, cheap to ship.
- **Respect system Focus/Do Not Disturb and quiet hours across every sound/notification trigger** — When macOS Focus mode is active, or after a user-configurable evening hour, automatically soften or skip the audible phase-end ring, habit anchor sounds, and backlog nudge sound, keeping only visual feedback — purely local time-of-day/OS-state checks, no new permissions or preference sprawl.  
  _Why:_ Extends the app's stated 'calm by default' philosophy from Pomodoro alone (where it was originally proposed) to every notification-producing subsystem at once.
- **Small local personalization bundle: radio volume, break-time auto-resume, and surfacing already-modeled fields** — Add an in-panel volume slider for the Lofi Radio (backed by AVPlayer.volume), let a break automatically resume the last-played station (completing the existing focus→ticking / break→lofi pause rule in the other direction), and surface two fields that are already fully modeled but never exposed in UI: a Settings 'how gently should DayBar nudge?' control backed by the existing EscalationThresholds, and a small per-task focus-count badge backed by the existing but unused pomodoroCount field.  
  _Why:_ All of these are cheap, local-only wins on top of data/logic that's already built and tested — no new persistence design, no new sync surface, just finishing work the codebase already anticipated.

---

## Full findings by subsystem

Every confirmed bug, UX issue, quality note, and feature idea, organized the way the codebase is organized.

### App Shell, Menu Bar & System Integration

_AppDelegate (Sources/DayBar/MenuBarController.swift) is the composition root for this subsystem: on launch it builds the single `AppState` (owning `DataStore`, `PomodoroEngine`, `NotificationScheduler`, the reminders/habit sync engines, `RadioPlayerManager`), sets the accessory activation policy, and builds one `NSStatusItem` plus one long-lived, non-activating `FloatingPanel` (`NSPanel`) hosting a single `TodayView` instance via `NSHostingView`/`NSVisualEffectView` — chosen explicitly over SwiftUI's `MenuBarExtra` because that failed to re-render reliably on `@Observable` changes. The same `AppState` instance is observed twice in parallel by two different mechanisms: SwiftUI's environment observation drives `TodayView`, while `MenuBarController`'s imperative `trackStatusUpdates()`/`withObservationTracking` loop separately drives the status-item glyph/title — so the two surfaces can (and, per findings below, already have started to) drift out of sync. `Hotkey.swift` registers a global `KeyboardShortcuts` hotkey that reveals the panel and bumps `AppState.quickAddFocusSignal`; `AppKitBridge.swift`, `IdleMonitor.swift`, and `LaunchAtLogin.swift` are small platform-facing utility layers (deep-links, swappable idle-time reader, `SMAppService` wrapper) that `AppState`/`SettingsView` mostly call into directly rather than exclusively through `AppKitBridge`, despite its own doc comment claiming to be the sole "containment point" for AppKit calls. `Preferences.swift` is the typed read layer over the same `UserDefaults` keys `SettingsView`'s `@AppStorage` bindings write, and feeds `PomodoroEngine` config, `NotificationScheduler` gating, the new Sound engines (`AlertSoundPlayer`/`TickingSoundPlayer`), and both reminders-sync engines' calendar scoping._

`2 confirmed bugs` · `6 UX issues` · `6 quality notes` · `4 feature ideas`

#### Confirmed bugs

**[MEDIUM] Outside-click monitor is leaked when showPanel() runs while the panel is already visible**  
`showPanel()` unconditionally does `outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(...)` without first removing any existing monitor. `togglePanel()` only calls `showPanel()` when `!panel.isVisible`, but the `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:...)` handler calls `self.showPanel()` unconditionally, regardless of current visibility.  
> **Failure scenario:** User already has the DayBar panel open, then taps a delivered system notification (e.g. a habit-anchor or phase-end banner). `didReceive` fires and calls `showPanel()` again, overwriting `outsideClickMonitor` with a brand-new global monitor while the previous monitor's reference is dropped — that first monitor can never be passed to `NSEvent.removeMonitor` again, so it stays registered with the system for the lifetime of the app, permanently consuming a monitor slot and firing an extra (harmless but wasteful) `hidePanel()` call on every future outside click. Repeating the sequence accumulates more leaked monitors indefinitely.  
`Sources/DayBar/MenuBarController.swift:252`

**[MEDIUM] Launch-at-login toggle silently reverts on failure with no user feedback**  
`LaunchAtLogin.setEnabled(_:)` is a `throws` function wrapping `SMAppService.mainApp.register()/unregister()`. Its only call site, `SettingsView`'s `.onChange(of: launchAtLogin)`, invokes it as `try? LaunchAtLogin.setEnabled(newValue)` and then unconditionally resets `launchAtLogin = LaunchAtLogin.isEnabled` — so any thrown error is discarded and the UI just snaps the toggle back to its previous state. The only failure state the Settings UI checks for is `LaunchAtLogin.requiresApproval` (`.requiresApproval` status), which does not cover a failed `register()` call.  
> **Failure scenario:** User runs DayBar from a location/build configuration where `SMAppService.mainApp.register()` throws (e.g. a build not properly registered as a Launch Services app, or a translocated/quarantined copy outside `/Applications`). They flip 'Launch DayBar at login' on in Settings; the toggle visibly flips back to off a moment later with zero explanation — no alert, no inline error text — leaving the user to conclude the feature is simply broken.  
`Sources/DayBarCore/System/LaunchAtLogin.swift:16`

#### Plausible, unverified

**[HIGH] Quick-add loses auto-focus after the panel is reopened via the menu bar icon (not the hotkey)** _(uncertain — could not be fully verified either way)_  
The quick-add `TextField` is force-focused from exactly two places: TodayView's one-shot `.onAppear` (`DispatchQueue.main.async { addFocused = true }`) and `.onChange(of: appState.quickAddFocusSignal)`. Only `revealForQuickAdd()` (the global-hotkey handler) bumps `quickAddFocusSignal`; `togglePanel()`/`showPanel()` — the path used every time the user simply clicks the status-bar icon — never touches it. Commit 27d6bea, which introduced `quickAddFocusSignal`, did so specifically because `onAppear` alone was already known to be insufficient for repeat reveals of this always-mounted `NSHostingView`/`NSPanel` (the fix was applied only to the hotkey path). Since the panel's `NSHostingView` is created once in `setupPanel()` and merely `orderOut`/`orderFront` toggled thereafter, `.onAppear` does not reliably refire on later icon-click opens.  
> **Failure scenario:** User clicks the menu-bar icon to open DayBar (not the ⌥⌘D hotkey), types and submits a task, then clicks the icon again to close and a third time to reopen. The quick-add field no longer has keyboard focus, so keystrokes go nowhere until the user manually clicks into the field — breaking the rapid multi-add ritual TodayView's own header comment calls the 'morning ritual'.  
`Sources/DayBar/MenuBarController.swift:186`

#### UX issues

- **[MEDIUM] Panel stays floating on top of other apps when switching away via keyboard/Mission Control** — `Sources/DayBar/MenuBarController.swift`  
  The only auto-dismiss mechanism is a global mouse-click monitor (`NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])`) installed in `showPanel()`. There is no `applicationDidResignActive`/window-resign handling. Since the panel is `.popUpMenu` level with `[.canJoinAllSpaces, .fullScreenAuxiliary]`, Cmd-Tabbing to another app or entering Mission Control leaves the DayBar panel floating above whatever the user switched to, unlike Control Center, Notification Center, or other menu-bar-style panels which dismiss on app switch.
- **[MEDIUM] "Drop" is styled destructive but has no confirmation and no visible undo path** — `Sources/DayBar/TodayView.swift`  
  In `TodoRow`'s actions menu, "Drop" uses `role: .destructive` right next to "Delay to tomorrow" and "Reset to to-do", with no confirmation dialog. `appState.drop()` only flips status to `.dropped` (soft-delete), but nothing in TodayView (or the referenced TaskHistoryView) surfaces dropped tasks or offers undo, so from the user's perspective a mis-click permanently and silently removes the task — inconsistent with every other action in the same menu being trivially reversible.
- **[MEDIUM] Icon-only controls have no accessibility labels** — `Sources/DayBar/TodayView.swift`  
  The header settings `Menu` (`Image(systemName: "gearshape")`), the per-row "..." actions `Menu` in both `TodoRow` and `HabitRow` (`Image(systemName: "ellipsis")`), and the Pomodoro strip's play/pause/stop/skip buttons all rely solely on bare SF Symbol image content with no `.accessibilityLabel`. VoiceOver users get raw symbol-name announcements (e.g. "ellipsis", "gearshape") instead of meaningful action names like "More actions" or "Pause focus session".
- **[LOW] Row action menus are only discoverable on mouse hover** — `Sources/DayBar/TodayView.swift`  
  Both `TodoRow` and `HabitRow` gate their "..." actions menu behind `.opacity(hovering ? 1 : 0)` driven by `.onHover`. There is no persistently visible affordance and no keyboard-focus-triggered reveal, so trackpad-less or keyboard-primary users have no visual cue that per-row actions (Edit, Delay, Drop, Skip habit, etc.) exist at all.
- **[LOW] Fixed-width, fixed-row-height panel does not respond to Dynamic Type** — `Sources/DayBar/MenuBarController.swift`  
  `panelWidth` is hardcoded to 320 in MenuBarController.swift and `TodayView` pins `.frame(width: 320)`; `desiredPanelHeight()` also hardcodes `rowHeight: CGFloat = 34` per task/habit row independent of actual rendered text size. A user with larger system text sizes gets truncated/clipped rows (titles already use `.lineLimit(1)`/`.lineLimit(2)`) rather than a taller panel, since the panel's content size is computed from constants, not from the hosted view's real fitting size.
- **[LOW] Escalation urgency is conveyed by color alone in the age pill** — `Sources/DayBar/TodayView.swift`  
  `AgePill` maps `EscalationTier` to only two states — `.secondary` (gray) or `.orange` — via `tier >= .aging ? .orange : .secondary`, with both text and background using the same hue at different opacities. For a colorblind user the "aging" vs. "fresh" distinction is a subtle orange/gray tint shift with no additional shape, weight, or icon cue.

#### Code quality & maintainability

- **MenuBarLabel (DayBarApp.swift) is dead code that has already drifted from the live status-item logic** — `Sources/DayBar/DayBarApp.swift`  
  `MenuBarLabel` is never referenced anywhere in the codebase, yet it duplicates the same symbol/text decision tree as `MenuBarController.updateStatusItem()` — and the two have already diverged: `MenuBarLabel` has no branch for `appState.radio.isPlaying` (the 'waveform'/'♪' state that `updateStatusItem()` does handle). Either delete it, or make `updateStatusItem()` actually render it through the hosting view so there is one implementation instead of two that can silently disagree.
- **Most of AppKitBridge is unused, contradicting its own doc comment** — `Sources/DayBarCore/System/AppKitBridge.swift`  
  `setAccessoryActivationPolicy()`, `activateApp()`, and `makeMenuBarWindowKey()` are never called; `MenuBarController.swift` calls `NSApp.setActivationPolicy(.accessory)` and `NSApp.activate(ignoringOtherApps: true)` directly instead, bypassing the 'containment point for the few unavoidable AppKit touchpoints' the file's header comment promises. `makeMenuBarWindowKey()` also encodes a stale assumption (`windows.first(where: { $0.isVisible && !$0.isMainWindow })`) left over from a pre-NSPanel architecture. Either route the live call sites through these helpers or delete the unused ones so the abstraction boundary the comment describes actually holds.
- **AppState.isPanelPresented is declared but never read or written** — `Sources/DayBarCore/State/AppState.swift`  
  Dead public state left over from an earlier iteration; safe to remove unless something was meant to set it from MenuBarController's show/hide paths.
- **desiredPanelHeight()'s hand-maintained magic-number layout duplicates TodayView's real SwiftUI layout** — `Sources/DayBar/MenuBarController.swift`  
  The chrome/row-height/section-header constants in `desiredPanelHeight()` are a hand-derived approximation of TodayView's actual layout, already missing the Tomorrow section (see bug report) and not Dynamic-Type-aware. Consider measuring the hosted view's real fitting size (e.g. via the hosting view's `intrinsicContentSize`/`fittingSize` after layout) instead of re-deriving it by hand each time a new section is added.
- **IdleMonitor's swappable closure is unsynchronized global mutable state** — `Sources/DayBarCore/System/IdleMonitor.swift`  
  `public static var secondsSinceLastInput: () -> TimeInterval` is mutated directly by tests (`IdleBreakSkipTests.swift`) with no actor isolation or `nonisolated(unsafe)` annotation. It's currently only ever swapped from one test file and read from the MainActor in production, so there's no live race today, but as more idle-related tests are added or the project tightens Swift 6 concurrency checking, this seam will need a proper annotation or a protocol-based injectable dependency instead of mutable global state.
- **PreferencesTests.swift covers a small fraction of Preferences.swift, missing the newest/most-changed keys** — `Tests/DayBarTests/PreferencesTests.swift`  
  The test's `keys` array only covers `workMinutes`, `shortBreakMinutes`, `longBreakMinutes`, `cyclesBeforeLongBreak`, `autoStartNext`, and `soundEnabled`. Nothing exercises `tickingSoundEnabled` (the property that replaced `soundName` in this working-tree change), the `intOrSet`-backed hour/minute keys used for morning/evening notification times, `eveningTime(on:calendar:)`, `moodAIEnabled`, or `effectiveHabitReminderCalendarIDs` — a direct unit test on the latter would have caught the empty-vs-unset bug reported above.

#### Feature ideas

- **A brief, calm 'Undo' after Drop** — Since `drop()` is already a soft-delete (status = `.dropped`, not an actual row deletion), surface a small, auto-dismissing 'Task dropped · Undo' affordance for a few seconds after the action, or a quiet 'Recently dropped' filter in Task History. No new destructive-action confirmation dialog needed — just make the existing reversibility visible.  
  _Why:_ Closes the 'irreversible-feeling destructive action with no confirmation' UX gap without adding a modal interruption, matching the calm-by-default philosophy better than an alert box would.
- **Quiet acknowledgment when the idle break-skip silently fires** — `skipBreakAndStartWork(silent: true)` (triggered by `evaluateIdleBreakSkip`) currently sets `suppressNextPhaseEndFeedback`, so the user gets zero sound, banner, or in-panel note that DayBar decided they were away and auto-started the next focus session. A single calm, non-modal sentence the next time the panel opens — e.g. 'You were away, so DayBar started your next focus session' — would keep the automatic behavior transparent without being alarming.  
  _Why:_ The feature already exists and is gentle in effect; the only gap is that it's currently invisible, which can feel surprising in retrospect ('why is a focus session already running?') even though nothing alarming happened.
- **Auto-hide the panel on app switch** — Add an `applicationDidResignActive`/active-space-change observer alongside the existing outside-click monitor so the panel dismisses when the user Cmd-Tabs away or enters Mission Control, matching Control Center/Notification Center conventions.  
  _Why:_ Directly closes the UX inconsistency where the panel currently floats above other apps' windows after a keyboard-driven app switch; purely a system-integration fix, no new UI surface.
- **Respect macOS Focus/Do Not Disturb for phase-end feedback** — When a macOS Focus mode is active (and it isn't DayBar's own notifications being filtered), quietly skip the audible phase-end ring and keep only the visual status-item change, rather than always playing `AlertSoundPlayer` whenever `soundEnabled` is on.  
  _Why:_ Extends the app's existing 'gentle, never surprising' stance to the user's current OS-level context, entirely local and config-free — no new preference UI required if it just defers to the system Focus state.

---

### Pomodoro, Notifications & Sound

_PomodoroEngine is a @MainActor, @Observable wall-clock timer whose single source of truth is `endDate`; a 1-second `Timer` only triggers redraws/`tick()` calls, so the countdown self-corrects across sleep (AppState.handleWake calls `pomodoro.tick()` then `refresh()`). AppState owns the engine and wires two closures: `onPhaseEnd` (records a `FocusSession` to DataStore, plays the AlertSoundPlayer ring, posts the NotificationScheduler banner, arms/clears `breakArmedAt` for the 30s idle-skip poller, and retries the end-of-day review prompt) and `onStateChange` (keeps TickingSoundPlayer and RadioPlayerManager mutually exclusive). NotificationScheduler is a thin wrapper around UNUserNotificationCenter that fully disables itself under XCTest (`center` returns nil whenever running in the test process), gates every call on its own `authorized` flag plus a `Preferences` toggle, and is driven by AppState's debounced `HabitNotifySignature` for habit anchors and a once-daily 14:00 backlog nudge. AlertSoundPlayer/TickingSoundPlayer/SynthesizedTone are independent, lazily-started AVAudioEngine wrappers with no shared session state, so an audio failure in one doesn't affect the other, but also fails silently (console print only) with no user-facing fallback or retry._

`4 confirmed bugs` · `7 UX issues` · `6 quality notes` · `4 feature ideas`

#### Confirmed bugs

**[HIGH] Stop button never records the elapsed focus session**  
TodayView's stop button calls `pomo.stop()` directly on the engine, bypassing AppState entirely. `PomodoroEngine.stop()` just resets phase/endDate/remaining and tears down the timer; it never calls `onPhaseEnd`, which is the only place `FocusSession` gets inserted into DataStore (AppState.handlePhaseEnd, gated on the callback firing). Pause+later skip correctly records elapsed time via `handlePhaseEnd`, but stop does not — the asymmetry means one control path silently loses analytics data the other preserves.  
> **Failure scenario:** User works for 24 of a 25-minute Focus session, then clicks the stop icon (right next to play/pause, no confirmation) instead of pause. `pomodoro.stop()` runs; `onPhaseEnd` never fires; `store.insert(FocusSession(...))` in AppState.handlePhaseEnd (line 772) is never reached. The 24 minutes vanish from Analytics/history with no record, no undo, and no user-visible indication anything was lost.  
`Sources/DayBarCore/Pomodoro/PomodoroEngine.swift:122`

**[HIGH] Completing a habit does not cancel its already-scheduled anchor notification**  
NotificationScheduler.scheduleHabitAnchors is documented to skip anchors for habits "already completed today" by checking `todayLogs`, but that recomputation only happens inside `rescheduleHabitNotificationsIfNeeded`, which is only invoked from the full `refresh()` (or `invalidateHabitNotifications()` + refresh). `AppState.toggleHabit` — the method wired to the tap gesture that marks a habit done — calls only `reloadLists`/`rebuildHabitCaches`; it never calls `refresh()`, `invalidateHabitNotifications()`, or `rescheduleHabitNotificationsIfNeeded`.  
> **Failure scenario:** A habit "Drink water" has notifyEnabled=true and anchorHour=12. At day-change, refresh() schedules the 12:00 anchor. At 10:00 the user taps the habit complete in the panel, invoking `toggleHabit` (AppState.swift lines 375-402) which never touches notification scheduling. At 12:00 the already-scheduled anchor still fires (`Sources/DayBarCore/Notifications/NotificationScheduler.swift` lines 109-131), reminding the user to do a habit they finished two hours earlier — directly contradicting the "skipped when already completed today" behavior the scheduler's own doc comment promises.  
`Sources/DayBarCore/State/AppState.swift:375`

**[MEDIUM] Backlog nudge can be permanently cancelled for the day by a post-14:00 refresh**  
`updateBacklogNudge` unconditionally removes the pending backlog notification first, then only re-adds it if `fireDate > now` (i.e. before 14:00 today). Any `refresh()` call after 14:00 — including the wake-from-sleep handler, which calls `refresh()` unconditionally — removes whatever was pending without any "already delivered / not yet due" check, and the guard then blocks re-scheduling for the rest of the day.  
> **Failure scenario:** The backlog nudge is scheduled for 14:00 while the Mac is awake at 13:00. The Mac then sleeps at 13:50 (before the notification fires) and wakes at 14:30. `NSWorkspace.didWakeNotification` triggers `handleWake()` (AppState.swift lines 763-766), which calls `refresh()` unconditionally, which calls `updateBacklogNudge(now: 14:30)`. The still-pending, never-delivered 14:00 notification is removed, and since `fireDate (14:00) > now (14:30)` is false, it is never rescheduled — the user with aging tasks gets no backlog nudge that day at all, even though they were away exactly during the window it should have fired.  
`Sources/DayBarCore/Notifications/NotificationScheduler.swift:138`

**[MEDIUM] First notification-permission grant does not populate backlog/habit-anchor schedules**  
`AppState.init` calls `refresh()` (which calls `updateBacklogNudge` and `rescheduleHabitNotificationsIfNeeded`) before `notifications.requestAuthorization()` is ever called from `applicationDidFinishLaunching` — so both no-op on `authorized == false`. When the user grants permission, `requestAuthorization`'s completion handler only calls `rescheduleRepeating()` (morning/evening); it never re-runs `updateBacklogNudge` or `rescheduleHabitAnchors`.  
> **Failure scenario:** A first-time user launches DayBar, sees the system prompt, and taps Allow. Morning/evening reminders get scheduled correctly (rescheduleRepeating runs on grant), but the backlog nudge and any habit anchor reminders due that day remain unscheduled until the next full `refresh()` is triggered by an unrelated event — midnight day-change, a Mac sleep/wake cycle, or an EventKit change — none of which is guaranteed to happen before the day ends. The user can go the entire first day with permission granted yet receive none of those two notification types.  
`Sources/DayBarCore/Notifications/NotificationScheduler.swift:29`

#### UX issues

- **[MEDIUM] An armed break looks identical to fully idle in the menu bar** — `Sources/DayBar/MenuBarController.swift (lines 61-86); Sources/DayBarCore/Pomodoro/PomodoroEngine.swift (lines 172-180)`  
  When a work phase ends without auto-start, PomodoroEngine deliberately leaves the next phase "armed but not running" (phase set, endDate=nil) so the panel can offer "Start break". But MenuBarController's status-item symbol/title logic only special-cases `pomo.isRunning`; an armed-but-unstarted break falls through to the same generic checklist glyph and blank title as a session that was never started at all. A user glancing at the menu bar has no way to tell "a break is waiting for you" from "nothing is happening" without opening the panel.
- **[MEDIUM] Play/pause and stop timer controls have no accessibility label or tooltip** — `Sources/DayBar/TodayView.swift (lines 506-515)`  
  Nearly every other icon-only button in TodayView.swift carries a `.help(...)` tooltip (quick-add "Add task", reminders sync icon, habit grace icon, todo-status tap hint, edit hint, skip-break). The Pomodoro strip's play/pause button and stop button are bare `Image(systemName:)` buttons with no `.help()` and no explicit `.accessibilityLabel`, breaking the pattern the rest of the app follows and leaving VoiceOver users to guess from the raw SF Symbol name.
- **[MEDIUM] Stop discards the in-progress session with no confirmation** — `Sources/DayBar/TodayView.swift (line 511); Sources/DayBarCore/Pomodoro/PomodoroEngine.swift (lines 122-129)`  
  The stop button is a small plain icon sitting directly next to play/pause, with no confirmation dialog, undo, or even a toast. Clicking it (or a mis-click meant for pause) silently throws away the entire elapsed focus time with zero visual acknowledgment that anything was lost — compare to pause, which is fully reversible.
- **[MEDIUM] Idle-driven break auto-skip gives the user zero feedback** — `Sources/DayBarCore/State/AppState.swift (lines 739-761)`  
  `evaluateIdleBreakSkip` silently skips an armed break and starts the next focus session when the user has been away past the threshold, explicitly suppressing the phase-end ring/notification via `suppressNextPhaseEndFeedback` (silent: true). The app never posts any acknowledgment (no toast, no banner) that this happened, so a user returning to their desk finds a running Focus countdown with no explanation of why — a confusing state for a subsystem whose whole design philosophy is "gentle, not alarming" nudges.
- **[LOW] "Play a sound when a timer ends" and "Notify when a Pomodoro phase ends" read as duplicates but are fully independent** — `Sources/DayBar/SettingsView.swift (lines 82, 95); Sources/DayBarCore/Notifications/NotificationScheduler.swift (line 92)`  
  The Sound section's toggle (ring via AlertSoundPlayer) and the Notifications section's toggle (silent banner via NotificationScheduler, `content.sound = nil`) both describe "a timer/phase ending" feedback and live under different section headers. A user turning one off reasonably expects the phase-end experience to change accordingly; toggling either one alone leaves the other's feedback (ring or banner) fully intact, which is easy to misread as a bug rather than by design.
- **[LOW] No way to preview the ticking sound before enabling it** — `Sources/DayBar/SettingsView.swift (lines 81-86)`  
  The ring has a "Test sound" button right next to its toggle, but the ticking-during-focus toggle has no equivalent preview — a user has to enable it and then start (or wait for) a real focus session to find out what it sounds like, and if they dislike it they've already interrupted a live session to turn it off.
- **[LOW] Notification-permission-denied warning is easy to miss** — `Sources/DayBar/SettingsView.swift (lines 142-147)`  
  The only indicator that morning/evening reminders and phase-end banners are silently non-functional is a `.caption`-sized, `.orange` line buried at the bottom of the Notifications Form section, with no icon, no bold weight, and no separate visual container — low-prominence for a state that quietly disables three separate features (morning/evening reminders, phase-end banner, backlog nudge, habit anchors).

#### Code quality & maintainability

- **NotificationScheduler has zero unit test coverage and is structurally untestable** — `Sources/DayBarCore/Notifications/NotificationScheduler.swift`  
  `center` returns nil whenever `XCTestConfigurationFilePath` is set in the environment, so every public method (`rescheduleRepeating`, `postPhaseEndBanner`, `rescheduleHabitAnchors`, `updateBacklogNudge`) becomes a no-op under XCTest — there is no NotificationSchedulerTests file, unlike TickingSoundGateTests/HabitNotifySignatureTests/EndOfDayReviewGate for the neighboring pure-logic gates. The scheduling *decisions* (backlog fire-time math, which habit anchors to keep) are pure and worth extracting into standalone functions (mirroring `TickingSoundGate`/`EndOfDayReviewGate`) so they can be tested without `UNUserNotificationCenter` at all.
- **scheduleHabitAnchors reads Calendar.current/Date() instead of an injected clock** — `Sources/DayBarCore/Notifications/NotificationScheduler.swift`  
  `scheduleHabitAnchors` computes `today` via `Calendar.current.startOfDay(for: Date())` even though its caller (`AppState.rescheduleHabitNotificationsIfNeeded`) already filtered `templates` using an injectable `now`/`calendar`. This makes the method impossible to unit test deterministically and introduces a real (if narrow) midnight-boundary race: the async round-trip through `getPendingNotificationRequests` means the day can roll over between the caller's filtering and this method's own re-check.
- **Notification identifier for the evening-review tap handler is duplicated as a hardcoded string** — `Sources/DayBar/MenuBarController.swift`  
  `NotificationScheduler.ID.evening` is `"evening.review"` but is `private`, so MenuBarController's `userNotificationCenter(_:didReceive:)` re-hardcodes the literal `"evening.review"` to detect the tap. Nothing keeps these in sync at compile time; renaming the identifier in one place silently breaks the other.
- **skipBreakAndStartWork double-transitions the engine when autoStartNext is on** — `Sources/DayBarCore/State/AppState.swift`  
  `skipBreakAndStartWork` always calls `pomodoro.skip(now:)` followed unconditionally by `pomodoro.start(.work, now:)`. When `config.autoStartNext` is true, `skip()`'s internal `handlePhaseEnd` already auto-starts the next work phase, so the explicit `start(.work,...)` re-runs `beginActivityIfNeeded`/`scheduleTimer`/`onStateChange` a second time for no behavioral gain — currently harmless because those calls are idempotent, but it's a fragile assumption that will bite the first time `start()` grows a side effect.
- **habitMilestoneMessage is reused as a generic ephemeral toast outside its name** — `Sources/DayBarCore/State/AppState.swift`  
  The property is documented as "Ephemeral banner after hitting a streak milestone," but `handlePhaseEnd` also assigns an unrelated string to it ("Focus ended — music paused") when radio pauses on focus end. Two unrelated ephemeral messages sharing one property/name risks one silently clobbering the other and confuses future readers about what the field is for; a generically-named `ephemeralBanner`/`toastMessage` would better reflect its actual multi-purpose use.
- **No tests at all for the new sound layer** — `Sources/DayBarCore/Sound/SynthesizedTone.swift`  
  AlertSoundPlayer, TickingSoundPlayer, and SynthesizedTone (all new/untracked files) have no corresponding test file. SynthesizedTone's buffer generation is pure math (frame counts, envelope decay, silence windows) and could be unit tested without AVAudioEngine playback — e.g. asserting `tickLoop`'s buffer is silent past `clickDuration`, or that `ringSequence`'s total duration matches `strikes`/`strikeDuration`/`gap` — catching regressions in the one part of this new code that's actually deterministic and cheap to verify.

#### Feature ideas

- **Quiet-hours auto-softening of the phase-end ring** — After a user-configurable hour (or detected system Focus/Do Not Disturb mode), automatically downgrade the phase-end ring to a shorter/softer single strike (or notification-only, no sound) instead of the full 3-strike ring — purely local time-of-day + Preferences logic, no new permissions or backend.  
  _Why:_ Fits the stated "calm by default" philosophy directly: it's an automatic accommodation rather than something the user has to remember to configure every evening, and it never escalates or nags.
- **Gentle acknowledgment when idle-skip auto-starts a session** — When `evaluateIdleBreakSkip` silently starts the next work phase because the user was away, surface a single low-key line via the existing ephemeral-banner mechanism (e.g. "Started your next focus session while you were away") the next time the panel opens, instead of leaving zero trace of the automatic transition.  
  _Why:_ Directly closes the "confusing silent state" UX gap identified above while staying calm — informational, not alarming, and reuses machinery that already exists.
- **Distinct, warmer acknowledgment for the long break** — `postPhaseEndBanner` currently sends identical "Break over. Back to focus." copy and the identical ring regardless of whether a short or long break just ended. Give the long break (earned every `cyclesBeforeLongBreak` sessions) slightly different, warmer copy/tone ("Nice stretch — take a longer break") to acknowledge the completed cycle.  
  _Why:_ Positive reinforcement without streak-shaming or competitive gamification — a one-line copy/tone change grounded entirely in local PomodoroEngine state that's already being tracked (`completedWorkCount`).
- **Optional focus recap line in the phase-end notification** — Append a short factual line to the existing phase-end banner body pulled from already-recorded FocusSession data for the day, e.g. "Focus done — 3rd session today," fully local and additive.  
  _Why:_ Purely informational, no new data collection or comparison to other days/users, keeps with local-first/no-cloud constraints, and avoids any guilt framing by only ever stating a neutral count.

---

### Daily Todos, Rollover & Day Math

_The subsystem centers on `DailyTodo` (a SwiftData `@Model`), which stores raw `statusRaw`/`priorityRaw`/`sourceRaw` plus two dates: the mutable `plannedForDate` (which day's list a todo appears in) and the immutable `originalPlannedDate` (the basis for age/escalation, computed live via `DayMath` + `EscalationModel`, never persisted per row). `DayMath` centralizes all start-of-day/day-difference arithmetic so every day-boundary comparison in the app goes through one DST/timezone-safe helper. `RolloverEngine`, invoked from `AppState.refresh()` (triggered on panel open, wake, `.NSCalendarDayChanged`, and Reminders-change notifications), is an idempotent `@MainActor` gate keyed on `AppMeta.lastProcessedDay`: once per new calendar day it re-queries `DataStore.overdueIncompleteTodos` and flips their status to `.carriedOver`, saving that alongside the day marker. `AppState` is the sole orchestrator — it owns the `Calendar`/`DataStore` shared by `RolloverEngine` and every todo-mutating intent (`addTodo`, `advanceTodo`, `delay`, `reschedule`, `drop`, etc.), keeps derived `@Observable` lists (`todayTodos`, `tomorrowTodos`, `carriedTodos`) in sync after every mutation, and feeds `overdueCount`/`worstTier` (via `EscalationModel`) into the menu-bar badge and `NotificationScheduler`'s backlog nudge. `DayLog` is a parallel once-a-day record written by the end-of-day review flow, snapshotting that day's `todayTodos` counts; its mere existence gates the auto-review prompt from firing twice._

`4 confirmed bugs` · `7 UX issues` · `8 quality notes` · `5 feature ideas`

#### Confirmed bugs

**[HIGH] Calendar/timezone is captured once at launch and never refreshed**  
AppState stores `calendar: Calendar = .current` in a `let` at init time and hands the same frozen struct to RolloverEngine, DataStore call sites, and every DayMath call throughout the app's lifetime. `Calendar.current` is a value-type snapshot resolved at the moment it's read, not a live binding — Foundation apps must re-fetch it (or listen for `NSSystemTimeZoneDidChangeNotification`) to track a later timezone change. AppState.observeSystem() only listens for `.didWakeNotification`, `.NSCalendarDayChanged`, and `.EKEventStoreChanged` — there is no timezone-change observer anywhere.  
> **Failure scenario:** User launches DayBar while in New York (EST) and leaves the menu-bar app running for days (its whole design encourages this). They fly to Tokyo and their Mac's timezone auto-updates to JST. DayBar's RolloverEngine, DataStore.todos(on:), and every escalation-age calculation keep computing 'midnight' using the stale EST offset captured at launch, so 'today'/'carried over' boundaries and the backlog-aging pill drift by up to 13-14 hours from the user's actual local day for as long as the app keeps running — todos silently roll over or fail to roll over at the wrong local time.  
`Sources/DayBarCore/State/AppState.swift:72`

**[HIGH] Completing a carried-over todo makes it vanish from the whole panel**  
RolloverEngine only ever mutates `status` on carry-over — it never advances `plannedForDate`. DataStore.todos(on:) (used for todayTodos/tomorrowTodos) filters by `plannedForDate` range but does NOT exclude completed items, while DataStore.overdueIncompleteTodos (used for carriedTodos) filters by `plannedForDate < today` but DOES exclude completed items (`completedDate == nil`). A carried-over todo's `plannedForDate` is still its original (past) day, so once it's completed it satisfies neither query.  
> **Failure scenario:** A task planned for Monday is left undone; Tuesday's rollover marks it .carriedOver (plannedForDate still Monday). On Tuesday the user opens the panel, sees it in 'CARRIED OVER' with a '1d' pill, and taps the checkbox twice (planned/carriedOver -> inProgress -> completed) to finish it. `advanceTodo` sets completedDate and status=.completed but never touches plannedForDate. `refresh()` reloads: it's excluded from carriedTodos (completedDate != nil) and excluded from todayTodos (plannedForDate == Monday, not Tuesday's range). The row disappears instantly with no checkmark/strikethrough moment and is not visible anywhere in TodayView for the rest of the day — only discoverable via the separate Task History sheet — making a just-completed action look like the task was deleted.  
`Sources/DayBarCore/State/AppState.swift:220`

**[MEDIUM] Backlog nudge notification can silently never fire for the whole day**  
`updateBacklogNudge` first unconditionally removes any pending backlog notification, then requires `fireDate (2pm today) > now` to schedule a new one; if the guard fails it just returns having already cleared the old request. It is called from every `AppState.refresh()` (launch/wake/day-change/panel-open), so if the first refresh of the day happens after 2pm there is no catch-up/next-day fallback.  
> **Failure scenario:** User has aging carried-over tasks and `backlogNotify` enabled, but doesn't open the DayBar panel (and the Mac doesn't wake) until 5pm that day — first `refresh()` of the day happens at 5pm. `updateBacklogNudge` computes fireDate = 2pm today, which is already in the past, so `fireDate > now` is false and the function returns with no notification scheduled — the gentle 'Tasks piling up' nudge (the app's only proactive backlog signal) never appears for that entire day, even though the aging count is nonzero and the preference is on.  
`Sources/DayBarCore/Notifications/NotificationScheduler.swift:140`

**[MEDIUM] SwiftData save/fetch errors are swallowed, and RolloverEngine reports success regardless**  
`DataStore.save()` catches `context.save()` errors and only `print()`s them — no error is thrown or surfaced back to callers. `RolloverEngine.performRolloverIfNeeded` uses `try?` on `store.appMeta()` and `store.overdueIncompleteTodos`, mutates in-memory `todo.status`/`meta.lastProcessedDay`, calls `store.save()`, and unconditionally returns `true` without checking whether the save actually persisted. Every other todo mutator in AppState (advanceTodo, resetTodo, delay, reschedule, drop, rename) follows the same 'mutate, save(), assume success' pattern.  
> **Failure scenario:** `context.save()` throws (e.g. disk full, or the on-disk store becomes momentarily locked/corrupted) during a nightly rollover. `DataStore.save()` prints the error to stdout (invisible for a backgrounded menu-bar app with no attached debugger) and returns normally. `performRolloverIfNeeded` still returns `true`; the running session's UI shows tasks as carried-over and `lastProcessedDay` as today even though nothing was actually written to disk. If the app is later force-quit or crashes before any subsequent successful save, the in-memory-only rollover is lost — on relaunch the same tasks and lastProcessedDay revert to their last truly-persisted values with zero indication to the user that anything went wrong.  
`Sources/DayBarCore/Rollover/RolloverEngine.swift:33`

#### Plausible, unverified

**[MEDIUM] Drop can silently erase an already-completed task from history/analytics** _(uncertain — could not be fully verified either way)_  
The 'Drop' menu item in TodoRow is shown unconditionally (outside the `if todo.isCompleted {...}`/`if !todo.isCompleted` gates that guard 'Reset'/'Delay'), so it can be invoked on a todo that is already `.completed`. `drop()` only flips status to `.dropped` and never clears completedDate, but every history/analytics query (`completedTodos(in:)`, `todos(plannedIn:)`) excludes `.dropped` regardless of completedDate.  
> **Failure scenario:** User finishes 'Write report' on Monday (completedDate set, status=.completed). A week later, while tidying up via the '...' menu, they tap 'Drop' on that same now-stale-looking row instead of a neighboring item. The task instantly disappears from Task History and its count is removed from that Monday's completed-task analytics bucket, retroactively changing a day's stats that were already 'in the books' — with no confirmation dialog and no way to see or undo it afterward.  
`Sources/DayBarCore/State/AppState.swift:294`

#### UX issues

- **[MEDIUM] Priority is modeled and displayed but never settable** — `Sources/DayBar/TodayView.swift, Sources/DayBar/TaskHistoryView.swift:109-115`  
  Priority (Low/Medium/High) drives sort order in DataStore.todos(on:) and is rendered as a colored dot in Task History, but no UI anywhere — quick-add, TodoRow's overflow menu, or rename mode — lets a user set a task's priority away from the default .medium. Every dot the user will ever see is the same medium color, a visual affordance implying variation that can never happen.
- **[HIGH] "Drop" is one click, irreversible, and unconfirmed** — `Sources/DayBar/TodayView.swift:374, Sources/DayBar/EndOfDayReviewView.swift:197`  
  Drop is exposed as a plain (non-confirmed) destructive menu item in TodayView's overflow menu and as a one-tap bordered button in EndOfDayReviewView — both trigger AppState.drop() immediately with no confirmationDialog/alert anywhere in the app. A dropped todo then disappears from every query used by the UI (today, tomorrow, carried-over, completed history, analytics) permanently, with no 'Dropped' list or undo to recover it.
- **[HIGH] Row actions (Edit/Delay/Bring-to-today/Drop) are mouse-hover-only, with an inconsistent pattern vs. Task History** — `Sources/DayBar/TodayView.swift:359-382`  
  TodoRow's '...' action menu is only visible via `.opacity(hovering ? 1 : 0)` bound to `.onHover`; there is no keyboard path, no VoiceOver accessibility action, and no right-click fallback. TaskHistoryView's HistoryTodoRow, showing the same kind of secondary action ('Bring to today'), instead uses a standard right-click `.contextMenu`, so the two nearly-identical row types teach the user two different interaction models. A keyboard-only or VoiceOver user cannot discover or trigger Edit/Delay/Bring-to-today/Drop on a today/carried-over row at all.
- **[MEDIUM] Status checkbox and menu buttons have no accessibility labels** — `Sources/DayBar/TodayView.swift:316-323`  
  The status-cycling checkbox (`Image(systemName: todoStatusIcon)`) and the '...' menu button expose only a mouse-hover `.help()` tooltip, with no `.accessibilityLabel`/`.accessibilityValue`. VoiceOver will read the raw SF Symbol name (e.g. 'circle, button' or 'ellipsis, button') instead of the task's actual state ('Not started', 'In progress', 'Done') or what tapping does.
- **[MEDIUM] Renaming a task requires a double-click gesture with no alternative** — `Sources/DayBar/TodayView.swift:348-350`  
  Editing a title only works via `onTapGesture(count: 2, perform: beginEdit)` on the title Text. There is no keyboard shortcut, no accessible custom action, and no visible 'edit' affordance besides a hover tooltip — VoiceOver and keyboard-only users have no way to rename a todo.
- **[LOW] Truncated titles have no way to read the full text without entering edit mode** — `Sources/DayBar/TodayView.swift:342-347`  
  Task titles are hard-limited to `lineLimit(2)` inside a fixed 320pt-wide panel, with no `.help(todo.title)` tooltip on the Text itself. Combined with macOS's system-wide larger-text accessibility setting, titles truncate more aggressively for exactly the users who need bigger text, and the only way to see the full title is the mouse-only double-click-to-edit gesture.
- **[LOW] In-progress state silently disappears overnight with no visual distinction from 'never started'** — `Sources/DayBar/TodayView.swift:405-415, Sources/DayBarCore/Rollover/RolloverEngine.swift:28-31`  
  RolloverEngine flips any non-completed, non-carried-over status (including .inProgress) to .carriedOver on the next day boundary. Because TodoRow's `todoStatusIcon`/`todoStatusColor` render .planned, .carriedOver, and .snoozed identically (plain open circle, secondary color, regular weight), a task the user was actively working on yesterday looks exactly like a task that was never touched, with zero indication that progress existed and reset.

#### Code quality & maintainability

- **DailyTodo.snoozedUntil is write-only and duplicates plannedForDate** — `Sources/DayBarCore/Model/DailyTodo.swift`  
  `snoozedUntil` is set in `delay()`/cleared in `reschedule()` but never read by any query, predicate, or view in the codebase — it carries no information not already captured by `plannedForDate`/`status`. Either surface it (e.g. distinguish 'proactively delayed' from 'planned' in the UI) or remove it to shrink the model and its SwiftData migration surface.
- **delayCount and pomodoroCount are dead fields** — `Sources/DayBarCore/Model/DailyTodo.swift`  
  `delayCount` is incremented in `AppState.delay()` but never displayed or used in escalation/analytics logic. `pomodoroCount` is declared, stored, and round-tripped through StoreDTO, but nothing in the codebase ever increments or reads it — it's pure scaffolding for a feature that was never wired up on either side. Both add persistent-model complexity with no current payoff.
- **EscalationThresholds/AppState.thresholds is unreachable from Settings** — `Sources/DayBarCore/Model/EscalationModel.swift`  
  The doc comment on EscalationThresholds explicitly promises 'the Settings intensity control can lower these later,' and `AppState.thresholds` is a mutable public property ready to receive a user preference, but no Settings UI or Preferences key exists to ever change it away from `.gentle`. Either wire it up (cheap, since the model/tests already exist) or remove the aspirational comment.
- **Silent-failure logging uses print() instead of a structured/visible channel** — `Sources/DayBarCore/Data/DataStore.swift`  
  DataStore.save() only calls `print("DayBar: save error: \(error)")` on failure. For a background menu-bar app this is effectively invisible to both users and the developer in production. Routing through os_log/Logger (and, ideally, surfacing a lightweight in-app 'couldn't save' state) would make the failure mode in the bugs above at least diagnosable.
- **Test gap: no rollover test covers .inProgress todos or the carriedOver re-complete/reset branch** — `Tests/DayBarTests/RolloverEngineTests.swift`  
  RolloverEngineTests covers .planned->.carriedOver and .completed-not-touched, but never asserts what happens to an .inProgress todo crossing a day boundary. TodoAdvanceTests only exercises the advance cycle for same-day todos, never the `todo.plannedForDate < today ? .carriedOver : .planned` branch in advanceTodo/resetTodo/toggleComplete that a past-due todo hits when completed/reopened — exactly the branch responsible for the 'vanishing carried-over todo' bug reported above. A test asserting a completed carried-over todo is still visible in some list would have caught it.
- **Test gap: dropped todos are never asserted immune to rollover** — `Tests/DayBarTests/RolloverEngineTests.swift`  
  overdueIncompleteTodos excludes `.dropped` via `statusRaw != dropped`, which is exactly what stops a dropped task from being resurrected as `.carriedOver`, but no RolloverEngineTests case creates a past-due `.dropped` todo and asserts it stays `.dropped` after `performRolloverIfNeeded`.
- **Test gap: DayMath.startOfDay/nextDay/isSameDay have no direct unit tests** — `Tests/DayBarTests/DayMathTests.swift`  
  DayMathTests only exercises `dayDifference` (including DST spring-forward and timezone cases). `startOfDay`, `nextDay`, and `isSameDay` are exercised only indirectly through AppState-level tests, so a DST/timezone regression specific to `nextDay` (e.g. its `?? date` fallback returning a non-normalized date) wouldn't be caught at the unit level where DayMathTests already proves the pattern is easy to test.
- **DataStore.completedTodos(in:) fetches the entire completed-todo table before filtering by date** — `Sources/DayBarCore/Data/DataStore.swift`  
  Unlike `todos(on:)`/`overdueIncompleteTodos`, which push the date bound into the `#Predicate`, `completedTodos(in:)` fetches ALL non-dropped completed todos unconditionally and then filters/sorts the range in Swift. As completion history grows over months this becomes an unbounded fetch on every Task History open and every analytics/mood bucket call.

#### Feature ideas

- **Quiet undo toast for Drop** — Replace (or complement) the current unconfirmed one-click Drop with a small, dismiss-on-tap toast ('Dropped "Write report" — Undo') that lingers ~6-8 seconds, instead of a modal confirmation dialog.  
  _Why:_ Keeps the one-tap speed the app currently has while removing the 'did that just disappear forever' anxiety the current unconfirmed, unrecoverable Drop causes — matches 'calm by default' better than an interruptive alert would.
- **Surface the already-modeled escalation intensity and focus-count fields** — Add a small Settings control ('How gently should DayBar nudge?') backed by the existing EscalationThresholds struct, and a subtle per-task '🍅×N' badge backed by the existing (currently unused) pomodoroCount field once a focus session completes while that task is in progress.  
  _Why:_ Both are pure UI work on top of data/logic that's already fully modeled and tested — low-risk, no new persistence design needed, and both are quiet/local, no gamification or comparison across users.
- **Weekly backlog check-in instead of only a daily 2pm nudge** — Once a week, show a single quiet panel banner or notification summarizing the full carried-over list with one-tap keep/reschedule-a-week/drop triage per item, complementing (not replacing) the existing daily aging nudge.  
  _Why:_ Gives aging tasks periodic, low-frequency attention without adding another daily notification — stays within the app's existing gentle, non-alarming nudge cadence rather than escalating noise.
- **A 'Someday' shelf for tasks that keep getting delayed** — Let a user move a repeatedly-delayed task into a low-visibility Someday list that's excluded from carry-over aging/escalation entirely but stays searchable and restorable — a middle ground between 'carried over forever, aging orange' and 'dropped and gone.'  
  _Why:_ Reframes 'not this week' as a neutral parking spot rather than either an escalating visual nudge or an irreversible deletion, fitting the calm/no-shame philosophy better than the current binary.
- **On-device backlog trend line in Analytics** — Chart the count of still-open carried-over tasks by age bucket over time (using the existing carryOverAgeInDays), so a user can see whether their backlog is trending up or down over weeks — purely local, no new data collection.  
  _Why:_ Gives a calm, factual long-term signal about follow-through without turning it into a competitive streak or guilt-inducing daily score.

---

### Habits Engine, Scheduling & UI

_HabitEngine.materializeIfNeeded (invoked from AppState.refresh(), which itself runs on init, panel appear, every todo/habit mutation, wake, day-change, and Reminders-change notifications) idempotently creates a HabitLog row per active, schedule-matching HabitTemplate for each day since AppMeta.lastHabitMaterializedDay, using HabitSchedule's weekday-bitmask logic to decide which days a template is "on." AppState then joins today's logs with templates via DataStore.todayHabits(...) into todayHabits, and separately rebuilds habitStreakEntries/heatmaps via the pure HabitAnalytics engine over a 365-day lookback; both caches feed TodayView (checkbox list), AnalyticsView (streak/heatmap via HabitHeatmapRow), EndOfDayReviewView (open-habits triage), and NotificationScheduler (per-habit anchor reminders, debounced by HabitNotifySignature). HabitRemindersSyncEngine is a parallel, optional bridge that pushes local template/log mutations to Apple Reminders and pulls remote title/cue/completion changes back through HabitReminderMapping, sharing the same ExternalSourceProvider instance AppState hands to the todo-level RemindersSyncEngine; all of this is MainActor-isolated and funnels through the single SwiftData DataStore, with HabitTemplate/HabitLog linked only by a raw templateId UUID (no SwiftData relationship/cascade)._

`6 confirmed bugs` · `6 UX issues` · `5 quality notes` · `5 feature ideas`

#### Confirmed bugs

**[HIGH] "Mark incomplete" on a skipped habit actually marks it completed**  
HabitRow's overflow menu shows the label "Mark incomplete" whenever `habit.log.isCompleted || habit.log.status == .skipped`, and both branches call the same `appState.toggleHabit(habit.log)`. But `toggleHabit`'s logic only resets to `.pending` when `log.isCompleted` is true; for a `.skipped` log it falls into the `else if log.status == .skipped` branch, which sets `log.status = .completed` and `log.completedAt = now` — the opposite of what the button promises. There is no other UI path (checkbox tap goes through the identical function) to move a log from `.skipped` back to `.pending`.  
> **Failure scenario:** User taps "Skip today" on "Meditate" (log.status becomes .skipped). They reopen the "..." menu and click "Mark incomplete", expecting to undo the skip. Instead `toggleHabit` sets the log to `.completed` (log.completedAt = now), which can even fire the streak-milestone banner ("7 days of Meditate — keep going.") for a day the user never actually did the habit, and the log can never be returned to `.pending` through the UI.  
`Sources/DayBarCore/State/AppState.swift:381`

**[HIGH] Disabling "Sync to Reminders" for a habit does not stop remote changes from silently overwriting it**  
`HabitRemindersSyncEngine.pull()` looks templates up via `store.habitTemplate(externalReminderIdentifier:)`/`habitTemplate(id:)` and `reconcileMirrorsOffPullSet` iterates `store.syncedHabitTemplates()` (`DataStore.swift:238`, defined as `externalReminderIdentifier != nil`) — neither path checks `template.remindersSyncEnabled`. Turning the per-habit toggle off in `HabitEditorSheet` never clears `externalReminderIdentifier`, and `AppState.updateHabitTemplate` only calls `habitRemindersSync.enqueuePush` when `template.remindersSyncEnabled` is true, so no "unlink" push ever happens either. The stale link is left fully live for pulls.  
> **Failure scenario:** Habit "Meditate" is synced (externalReminderIdentifier="abc"). User opens the habit editor, turns "Sync to Reminders" OFF, saves — `remindersSyncEnabled=false` but `externalReminderIdentifier` is untouched. Days later the user (or another of their devices via iCloud) marks the still-existing "Meditate" reminder complete in Apple Reminders. The next periodic `reconcileIfNeeded()` still finds the template via `habitTemplate(externalReminderIdentifier:)`, applies `HabitReminderMapping.applyCompletion`, and silently flips today's local log to `.completed` — even though the user explicitly disabled sync for that habit.  
`Sources/DayBarCore/External/Habits/HabitRemindersSyncEngine.swift:148`

**[MEDIUM] A transient AppMeta fetch failure silently empties the entire Habits panel and zeroes streaks**  
`HabitEngine.materializeIfNeeded` does `guard let meta = try? store.appMeta() else { return false }` — any SwiftData fetch error causes the whole method to no-op with no logging or user-visible error. `DataStore.todayHabits(on:calendar:)` then `compactMap`s out any template with no log for today, so the panel's `todayHabits` becomes empty and shows the same "No habits yet — add one in Settings." copy as a genuinely empty list. `HabitAnalytics.currentStreak` compounds this: when today's log is missing entirely (as opposed to present-but-pending), the loop's special-case-to-yesterday branch never triggers (`if let todayLog = byDay[today], todayLog.status != .completed` requires a log to exist), so the very next line `guard let log = byDay[checkDay] else { break }` returns a streak of 0 instead of falling back to yesterday's real streak.  
> **Failure scenario:** `store.appMeta()` throws once (e.g. a transient SwiftData context error during a busy save cycle). `materializeIfNeeded` returns `false` without inserting today's logs. The user opens the panel and sees "No habits yet — add one in Settings." for all of their configured habits, and if they open Statistics before the next successful materialization, any habit's displayed current streak reads 0 despite an unbroken multi-week history, with no error surfaced anywhere.  
`Sources/DayBarCore/Habits/HabitEngine.swift:20`

**[MEDIUM] First push of a newly-synced habit drops today's already-completed status**  
`HabitReminderMapping.dto(from:calendar:referenceDay:)` hardcodes `isCompleted: false`. `HabitRemindersSyncEngine.processPushQueue`'s "update" branch (existing `externalReminderIdentifier`) explicitly overrides `dto.isCompleted`/`dto.completionDate` from today's log, but the "create" branch (no `externalReminderIdentifier` yet) uses the dto as-is and never applies that override.  
> **Failure scenario:** User completes "Drink water" today (log.status = .completed), then later that same day enables "Sync to Reminders" for it in the habit editor. The next reconcile hits the create branch (`externalReminderIdentifier` is still nil), builds the DTO via `HabitReminderMapping.dto(from:...)` with `isCompleted` hardcoded false, and creates the Apple Reminders item as not-completed — silently disagreeing with DayBar's own state for the rest of the day.  
`Sources/DayBarCore/External/Habits/HabitRemindersSyncEngine.swift:93`

**[MEDIUM] A blank title on the remote Reminders item can silently wipe the local habit's title**  
`pull()` filters incoming DTOs with `where !dto.title.isEmpty` before calling `seen.insert(dto.externalIdentifier)`, so a reminder whose title was cleared never enters `seen`. `reconcileMirrorsOffPullSet` then treats it as "not seen", re-fetches it directly via `provider.fetchHabitReminder(externalIdentifier:)` with no title-emptiness guard, and calls `HabitReminderMapping.applyMetadata`, which does `template.title = dto.title` unconditionally.  
> **Failure scenario:** A habit "Meditate" is synced to Reminders. On another device (via iCloud) the user accidentally clears the reminder's title field, leaving it blank but not deleting the reminder. The next reconcile's `pull()` skips it from `incoming`/`seen` due to the empty-title filter, then `reconcileMirrorsOffPullSet` re-fetches it by ID and calls `applyMetadata`, setting `template.title = ""`. The habit now shows as a blank row in both the Today list and Settings with no indication of what happened or how to recover the name.  
`Sources/DayBarCore/External/Habits/HabitRemindersSyncEngine.swift:191`

**[MEDIUM] Weekday/weekend-scheduled habit anchor notifications can fire on off-schedule days**  
`NotificationScheduler.scheduleHabitAnchors` calls `addCalendar(id:hour:minute:...)`, which builds `UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)` from only `hour`/`minute` DateComponents — no weekday component — so once scheduled, the OS fires it every single day regardless of the habit's schedule. Correction only happens when `AppState.refresh()` runs (day-change, wake, or app relaunch) and `HabitNotifySignature` differs because the filtered `templates` list (`.filter { $0.isScheduled(on: now) }` in `rescheduleHabitNotificationsIfNeeded`) changed.  
> **Failure scenario:** User sets a "Weekdays" habit's anchor reminder for 8:00am. It fires correctly Monday–Friday. If the Mac is asleep or DayBar isn't relaunched before 8:00am Saturday (the OS-level notification daemon delivers scheduled `UNCalendarNotificationTrigger`s independently of the host app process), the user gets a "Habit reminder" banner on Saturday morning for a habit that is explicitly not scheduled that day — a jarring, off-schedule notification the app's own "calm by default, never alarming" philosophy is meant to avoid.  
`Sources/DayBarCore/Notifications/NotificationScheduler.swift:109`

#### UX issues

- **[HIGH] Archiving a habit is irreversible from the UI, with no confirmation** — `Sources/DayBar/HabitsSettingsSection.swift`  
  HabitsSettingsSection's "Archive habit" button has role: .destructive but shows no confirmation dialog before firing appState.archiveHabitTemplate(template). Worse, HabitsSettingsSection.reload() filters to `.filter(\.isActive)`, so an archived habit disappears from Settings entirely and there is no "unarchive"/"restore" control anywhere in the app (AnalyticsView only ever displays archived habits read-only, grayed out with an "archived" label). A user who archives the wrong habit, or misreads the destructive button, has no path back except manually editing the SwiftData store.
- **[HIGH] Skipped and pending habits look identical in both today lists** — `Sources/DayBar/TodayView.swift`  
  HabitRow (TodayView) renders the leading icon as `habit.log.isCompleted ? "checkmark.circle.fill" : "circle"` — a `.skipped` log and a never-touched `.pending` log both render as a plain gray "circle" with no strikethrough, badge, or label distinguishing them. The same is true of the "OPEN HABITS" list in EndOfDayReviewView, which always shows a plain "circle" icon regardless of skipped vs pending. A user who explicitly chooses "Skip today" gets no visible confirmation the choice registered and cannot tell, at a glance, which habits they still need to act on versus which they already dismissed for the day.
- **[MEDIUM] Habit row actions menu is mouse-hover-only with no accessible labels** — `Sources/DayBar/TodayView.swift`  
  The "..." menu (Skip today / Mark incomplete) in HabitRow is revealed only via `.opacity(hovering ? 1 : 0)` driven by `.onHover`, so keyboard-only and VoiceOver users have no visible affordance to discover it, and neither the checkbox button nor the menu carries an `.accessibilityLabel` — VoiceOver would announce raw SF Symbol semantics ("circle", "ellipsis") rather than something like "Mark Meditate complete" or "More actions for Meditate."
- **[MEDIUM] Custom weekday picker has two indistinguishable "T" and two indistinguishable "S" buttons** — `Sources/DayBar/HabitsSettingsSection.swift`  
  The custom-schedule weekday picker renders `["S","M","T","W","T","F","S"]` as plain Buttons with no `.help()` tooltip or `.accessibilityLabel`. Sunday/Saturday both read "S" and Tuesday/Thursday both read "T" with nothing to disambiguate them for sighted users glancing quickly or for VoiceOver users at all.
- **[MEDIUM] 28-day consistency heatmap conveys state through color alone, with no tooltip or accessibility label** — `Sources/DayBar/HabitHeatmapRow.swift`  
  HabitHeatmapRow renders each day as a small RoundedRectangle whose only signal is fill color/opacity (green completed, faint green grace-used, gray skipped/off-grace, near-invisible gray for unscheduled) — there is no `.help()` tooltip and no per-cell accessibility label, unlike the adjacent streak pill in HabitRow which does have `.help(...)`. Colorblind users and VoiceOver users get essentially no information from the densest, least self-explanatory element in the Habits UI (which date a cell represents, or why it's colored as it is).
- **[MEDIUM] "No habits yet" empty state is indistinguishable from a silent load failure** — `Sources/DayBar/TodayView.swift`  
  "No habits yet — add one in Settings." is shown identically whether the user genuinely has zero habits or (see corresponding bug) a transient `try? store.appMeta()`/materialization failure silently produced zero logs for today. There is no error state, retry affordance, or any way for the user to tell the two situations apart.

#### Code quality & maintainability

- **backfillFromTemplateCreation re-walks each template's entire history on every materialize call** — `Sources/DayBarCore/Habits/HabitEngine.swift`  
  `HabitEngine.materializeIfNeeded` calls `backfillFromTemplateCreation(templates:through:)` unconditionally on every invocation (i.e. on nearly every `AppState.refresh()` — panel open, every todo/habit mutation, wake, day-change), which loops from each active template's `createdDate` through today, calling `materializeDay` (a SwiftData fetch) for every single day, even when `lastHabitMaterializedDay == today` and nothing has changed. For a long-lived habit this is O(templates × days-since-creation) of redundant fetches on every refresh; it should short-circuit once `meta.lastHabitMaterializedDay == today` and no new templates were added since.
- **DataStore.delete(_:HabitTemplate) is unreachable dead code with no cascade story** — `Sources/DayBarCore/Data/DataStore.swift`  
  `HabitTemplate` and `HabitLog` are linked only by a raw `templateId: UUID`, not a SwiftData `@Relationship`, so `DataStore.delete(_ template:)` (never called from any UI path today) would leave orphaned `HabitLog` rows if a future "permanently delete" feature used it. Either wire a real relationship/cascade before exposing hard delete, or remove the dead API.
- **Inconsistent tooltips between HabitsSettingsSection and TodayView for the same icons** — `Sources/DayBar/HabitsSettingsSection.swift`  
  The Reminders-sync (`list.bullet`) and anchor (`bell.fill`) icons in `HabitsSettingsSection`'s row have no `.help()` tooltip, while the equivalent Reminders-sync icon in `TodayView.HabitRow` does (`.help("Synced with Reminders")`). Adding the same tooltip to the settings list would make the two views consistent.
- **HabitEditorSheet's time picker binding uses Calendar.current instead of the injected calendar** — `Sources/DayBar/HabitsSettingsSection.swift`  
  `timeBinding` calls `Calendar.current.date(bySettingHour:...)` directly rather than accepting/using the app's injected `Calendar`, breaking the explicit-calendar-injection convention documented in `DayMath` (used so tests and non-default time zones behave predictably). Low runtime impact today since `AppState`'s default calendar is also `.current`, but worth aligning for consistency and testability.
- **addHabitTemplate's sortOrder can collide after archiving a non-last habit** — `Sources/DayBarCore/State/AppState.swift`  
  `sortOrder` is set to `activeHabitTemplates().count`, not `max(sortOrder) + 1`. Archiving a habit that isn't the last one leaves a gap, so the next new habit's `sortOrder` can collide with an existing active template's `sortOrder`, silently relying on the `createdDate` secondary sort to keep ordering deterministic. Low impact today (no drag-reorder UI exists), but worth fixing if reordering is ever added.

#### Feature ideas

- **Unarchive a habit** — Add a lightweight "Archived habits" list (e.g. in Settings or Analytics) with a "Restore" action that flips `isActive` back to true, directly closing the irreversibility gap found in this audit.  
  _Why:_ Fully local (just flips an existing boolean already retained for analytics), no new infrastructure, and directly fixes a concrete UX/data-safety gap rather than adding a new surface.
- **Pause a habit for a stretch of days (vacation mode)** — A per-habit "Pause until…" action that temporarily excludes it from materialization/streak-breaking for a chosen date range, distinct from the existing per-day "Skip" (which still consumes weekly grace). While paused the habit is simply omitted from Today and from streak/grace accounting for those days rather than being marked skipped or pending.  
  _Why:_ Extends the existing schedule/grace machinery (HabitSchedule, HabitAnalytics) without new backend concepts, and matches the stated "gentle, never a wall of red" philosophy by letting real-life interruptions (travel, illness) not read as failure.
- **Quiet weekly habit summary instead of only daily anchors** — A single, once-a-week local notification or in-panel card ("3 of 4 habits kept a streak this week") computed entirely from the existing HabitAnalytics buckets/streaks, shown alongside — not replacing — the opt-in daily anchor reminders.  
  _Why:_ Purely a local computation over data the app already has; reinforces consistency positively over a longer horizon without adding daily notification noise, fitting the calm/no-guilt design philosophy explicitly called out for this app.
- **Group the Today habit list by cue text** — Cluster habits under lightweight headers derived from their existing `cueText` (e.g. "After morning coffee", "Before bed") rather than a single flat list, so the ritual ordering the user already described when creating the habit is visible in the panel itself.  
  _Why:_ Uses data the model already stores (`HabitTemplate.cueText`); no new fields, no cloud, purely a presentation change that reinforces the app's cue-based habit-formation framing.
- **Duplicate an existing habit as a starting point** — A "Duplicate" action in the habit editor/settings list that pre-fills a new habit's title, icon, cue, and schedule from an existing one (e.g. "Read (English)" → "Read (Spanish)"), leaving history untouched.  
  _Why:_ Small, purely local quality-of-life addition that reduces friction in HabitsSettingsSection without introducing any new sync, notification, or gamification surface.

---

### Analytics & Charts (Swift Charts, hover interaction)

_The Analytics subsystem is a pure read/aggregate layer over SwiftData: `Analytics`, `HabitAnalytics`, and `MoodAnalytics` (Sources/DayBarCore/Analytics/) are dependency-free, `Calendar`-driven functions that turn raw models (`DailyTodo`, `FocusSession`, `HabitLog`, `DayLog`) into `Sendable` bucket structs (`StatBucket`, `HabitStatBucket`, `MoodStatBucket`) plus streak/heatmap data, with no UI or persistence knowledge — this is why they're cleanly unit-tested. `AppState` (the single `@MainActor` state owner) is the only bridge: it fetches from `DataStore` with `try?` and calls into these pure functions on demand (`statBuckets`/`habitStatBuckets`/`moodStatBuckets`/`habitStreaks`/`completedHistory`), and additionally caches habit streak/heatmap results in `habitStreakEntries` during `refresh()` for reuse by the today panel. `AnalyticsView` (SwiftUI + Swift Charts) re-reads these as plain computed properties on every render and draws six chart types across three tabs; the new `HoverableChart` (Sources/DayBar/ChartHoverOverlay.swift) wraps each chart with a `chartOverlay` + `onContinuousHover` gesture that converts a cursor location to a plot x-value via `ChartProxy`, then snaps it to the nearest bucket date using the pure, tested `ChartHoverMath.nearestDate`, feeding that date back into the chart's builder closure to draw a crosshair `RuleMark` and `ChartHoverTooltip`. There is no ViewModel layer — the view talks straight to `AppState` — and `TaskHistoryView` is a sibling read-only view over the same `DataStore` for completed-task browsing._

`1 confirmed bugs` · `8 UX issues` · `5 quality notes` · `4 feature ideas`

#### Confirmed bugs

**[MEDIUM] Habits 'avg/day' stat is mislabeled — actually avg per selected bucket period**  
`habitsSummary` (AnalyticsView.swift lines 133-145) computes `dayCount = habitBuckets.filter { $0.planned > 0 }.count` and `avgPerDay = completed / dayCount`, but `habitBuckets` is bucketed by the currently selected `granularity` (day/week/month), so `dayCount` is really a count of buckets, not of days, whenever granularity isn't `.day`. The stat label is hardcoded to 'avg/day' regardless.  
> **Failure scenario:** User has one daily habit completed every day and switches the Habits tab's Range picker to 'Week' (12 weekly buckets, count(for: .week) = 12). Each bucket's `completed` sums to ~7 (one completion per day for 7 days), so `completed` totals ~84 across 12 buckets and `dayCount` = 12 (buckets with planned>0), giving `avgPerDay = 84/12 = 7`. The UI displays '7' under the label 'avg/day' even though the user completes the habit exactly once per day — the number overstates daily consistency by roughly 7x and never reflects the true per-day average once granularity is Week or Month.  
`Sources/DayBar/AnalyticsView.swift:138`

#### UX issues

- **[MEDIUM] No empty-state messaging anywhere in Statistics** — `Sources/DayBar/AnalyticsView.swift`  
  A brand-new user (or one who hasn't logged habits/mood yet) opens Statistics and sees flat zero-height bars for 14 days, a dashed 'Neutral' line with no data on Mood, and a Habits tab whose 'CONSISTENCY (28 DAYS)' and 'STREAKS' sections render only their caption headers with zero rows underneath — nothing explains this is expected for a new user. TaskHistoryView.swift (lines 58-64) has an explicit `emptyState` ('No completed tasks in the last 30 days.') for the exact same situation, but AnalyticsView.swift has no equivalent for tasksContent/habitsContent/moodContent, so the two sibling read-views feel inconsistent.
- **[MEDIUM] Mood chart shows a cold numeric score with no emoji/legend** — `Sources/DayBar/AnalyticsView.swift`  
  moodTrendChart and moodSummary (AnalyticsView.swift lines 196-233) plot/label mood purely as a signed number ('Score 1.3', 'avg score 1.3', y-axis ticks -2..2) with zero mapping back to the emoji vocabulary the rest of the app uses for mood (EndOfDayReviewView.swift lines 130-138 shows MoodTag.emoji + displayName for every mood entry point). A user has to mentally translate a number into a feeling with no on-screen aid, which breaks the app's warm/emoji-forward voice right where reflection matters most.
- **[LOW] Unexplained 'Target' reference line on completion charts** — `Sources/DayBar/AnalyticsView.swift`  
  Both 'Completion rate' and 'Habit completion rate' charts draw a dashed green RuleMark at 0.8 (AnalyticsView.swift lines 321-323 and 352-354) with no legend, caption, or tooltip explaining what the line means or why 80% was chosen — it's an unlabeled, hardcoded external 'target' floating on a chart in an app whose stated philosophy is 'calm by default, never a wall of red'; users below the line have no context for whether/why that matters.
- **[LOW] Statistics always reopens on Tasks/Day, discarding the user's last view** — `Sources/DayBar/TodayView.swift`  
  `tab` and `granularity` are plain `@State` on AnalyticsView (lines 15-16), and TodayView.swift's `.sheet(isPresented: $showStats) { AnalyticsView(appState: appState) }` (lines 64-66) constructs a brand-new AnalyticsView every time the sheet opens, so a user who habitually checks e.g. Habits + Week loses that selection every single time they close and reopen the panel — for a small daily-ritual utility this adds friction to a frequently repeated action.
- **[HIGH] No VoiceOver support for any chart data** — `Sources/DayBar/AnalyticsView.swift`  
  None of the Chart views in AnalyticsView.swift use `.accessibilityChartDescriptor`, `.accessibilityLabel`, or `.accessibilityValue`, and the hover crosshair/tooltip (the only way to read exact per-day values) is driven exclusively by `onContinuousHover`, a mouse-only gesture with no keyboard or VoiceOver equivalent (ChartHoverOverlay.swift lines 24-51). A VoiceOver user gets a chart with no way to inspect any value at all — the six charts and the habit heatmap are effectively invisible to assistive technology.
- **[MEDIUM] Habit heatmap distinguishes 'grace used' vs 'skipped' by subtle opacity alone** — `Sources/DayBar/HabitHeatmapRow.swift`  
  HabitHeatmapRow.color(for:) (HabitHeatmapRow.swift lines 43-60) differentiates completed/skipped/pending-with-grace/empty cells using only fill-color opacity on similar hues (e.g. skipped = `.secondary.opacity(0.25)` vs. grace-used pending = `.green.opacity(0.35)`), with no pattern, icon, or accessibility label per cell. This is a meaningful distinction (did the day consume the weekly grace slot or not) that's very hard to read at a glance and unreadable for colorblind or low-vision users, and each `RoundedRectangle` cell carries no VoiceOver information at all.
- **[LOW] Fixed chart/window sizing doesn't accommodate larger Dynamic Type** — `Sources/DayBar/AnalyticsView.swift`  
  The window is pinned to `.frame(width: 460, height: 640)` (AnalyticsView.swift line 92) and every chart section is pinned to `.frame(height: 150)` (chartSection, line ~255) regardless of text size. Because the labels use Dynamic-Type-aware fonts (.caption2, .title3, etc.) but the containers around them don't grow, larger system font sizes make axis labels, tooltips, and stat rows more likely to clip or overlap within the fixed 150pt chart band.
- **[LOW] Mood chart's hover crosshair can snap to a distant, unrelated day** — `Sources/DayBar/AnalyticsView.swift`  
  moodTrendChart only feeds `scoredDates` (days that actually have a mood average) into `HoverableChart` as hover candidates (AnalyticsView.swift line 206-207), and `ChartHoverMath.nearestDate` has no maximum-distance cutoff (ChartHoverMath.swift lines 8-10) — it always returns *some* candidate, however far. On a sparsely-logged week, hovering in the middle of an empty gap snaps the crosshair and tooltip to whichever logged day happens to be closest, which can be visually far from the cursor and easy to misread as 'today's mood' when it isn't.

#### Code quality & maintainability

- **Analytics buckets are refetched from SwiftData on every access site instead of once per render** — `Sources/DayBar/AnalyticsView.swift`  
  `buckets`, `habitBuckets`, and `moodBuckets` in AnalyticsView.swift (lines 26-36) are computed properties that call `appState.statBuckets(...)` / `appState.habitStatBuckets(...)` / `appState.moodStatBuckets(...)` — each of which does a full SwiftData fetch plus aggregation. `tasksContent` alone references `buckets` from `tasksSummary`, `plannedVsCompleted`, `completionRate`, `focusMinutes`, and `sessionsChart` — 5 separate fetch+aggregate passes for a single render whenever `tab`/`granularity` changes. Hoist these into a `let` at the top of `tasksContent`/`habitsContent`/`moodContent` (or cache in `@State`) and pass the value down instead.
- **habitStreaks() is called separately three times per Habits-tab render** — `Sources/DayBar/AnalyticsView.swift`  
  `habitsSummary`, `consistencySection`, and `streakSection` (AnalyticsView.swift lines 133-186) each independently call `appState.habitStreaks()`. It's cheap today (a cached array), but it's still needless duplication — compute once (`let entries = appState.habitStreaks()`) and thread it through.
- **Point.id = UUID() defeats stable identity for chart data** — `Sources/DayBar/AnalyticsView.swift`  
  The private `Point` struct used by `plannedVsCompleted` and `habitsDoneChart` (AnalyticsView.swift lines 259-264) assigns `let id = UUID()` at init time, and the `points` array is rebuilt from scratch on every render — so every bar gets a brand-new identity every time, even when the underlying date/type/count are unchanged. Prefer a stable id derived from `date` + `type` so `ForEach`/Charts diffing reflects real value changes rather than treating every render as an entirely new dataset (this also sets up any future bar-transition animation to work correctly).
- **Hover/tooltip/RuleMark block is duplicated near-verbatim six times** — `Sources/DayBar/AnalyticsView.swift`  
  Every chart builder (plannedVsCompleted, completionRate, habitCompletionRate, habitsDoneChart, focusMinutes, sessionsChart, moodTrendChart) repeats the same `if let hovered, let bucket = ...First(where:) { RuleMark(...).opacity(0).annotation(...) { ChartHoverTooltip(...) } }` shape with only the tooltip line text differing. Extracting a small generic helper — e.g. `hoverAnnotation<Bucket>(hovered:, buckets:, lines: (Bucket) -> [String])` — would remove ~60 lines of copy-pasted structure and the risk of one call-site drifting (e.g. forgetting the `unit: xUnit` on the RuleMark) as new charts are added.
- **HoverableChart never resets state when its data changes** — `Sources/DayBar/ChartHoverOverlay.swift`  
  Add `.onChange(of: dates) { hoveredDate = nil }` (or key the view with `.id(dates)`) inside `HoverableChart` (ChartHoverOverlay.swift lines 24-51) so a granularity/tab change can never leave a stale crosshair on screen — this directly fixes the stale-hover bug reported above at the root rather than relying on the next mouse move to correct it.

#### Feature ideas

- **Legend/scale strip under the mood chart** — Render a small static row of the 5 emoji tiers (e.g. 😞/😐/😊 with their score ranges) directly under the mood trend chart, and swap the numeric 'Score 1.3' tooltip line for the nearest MoodTag's emoji + displayName where possible.  
  _Why:_ Keeps the mood chart consistent with the emoji-first vocabulary already used in the end-of-day review, and removes the need to mentally translate a bare number into a feeling — a small, local, no-cloud change that fits the app's warm tone.
- **Click-to-pin tooltip alongside hover** — Let a click on a chart pin the currently-hovered tooltip in place (toggle off on a second click or Escape), independent of continued mouse movement, and expose the same value via a VoiceOver-readable label per data point (`accessibilityChartDescriptor` or per-mark `accessibilityLabel`/`accessibilityValue`).  
  _Why:_ Trackpad/mouse hover-only interaction currently excludes VoiceOver and keyboard-only users entirely from ever reading exact chart values; a pinned/keyboard-accessible alternative closes that gap without requiring a redesign.
- **Rolling personal-average reference line instead of a fixed 80% target** — Replace (or let users toggle between) the hardcoded 0.8 'Target' RuleMark on the completion-rate charts with a computed rolling average of the user's own last N periods, labeled 'your average' rather than 'target'.  
  _Why:_ A fixed external target number can read as judgmental in a philosophy that's explicitly 'never a wall of red'; a self-referential baseline is calmer, more meaningful, and needs no new data source — everything is already local.
- **'Away' / paused-day markers on charts** — Let a user mark a day (or date range) as intentionally away/off (vacation, sick day) from the Statistics view or Settings; excluded days render as a neutral hatch/gray band on charts and heatmaps instead of counting as a 0% or broken-streak day.  
  _Why:_ Keeps the habit heatmap and streaks gentle rather than punishing for planned breaks — directly serves the stated 'gentle, escalating, never alarming' design philosophy, fully local, no gamification.

---

### End-of-Day Review & AI-Assisted Mood Tracking

_The end-of-day review is a SwiftUI sheet (EndOfDayReviewView) presented from TodayView via appState.presentEndOfDayReview, toggled either automatically (AppState.maybePromptEndOfDayReview, called from refresh() and from the Pomodoro engine's work-phase-end callback) or manually ("Review day..." menu item / evening notification tap in MenuBarController). The auto-popup decision is delegated to the pure, well-tested EndOfDayReviewGate.shouldPresent, fed with hasReviewedToday (derived from DataStore.hasDayLog), today's todo count, the evening-time preference, an in-memory snooze timestamp, and the live Pomodoro running state. The view reads/writes appState.todayTodos/carriedTodos/todayHabits (mutated via toggleComplete/delay/drop/toggleHabit, each calling store.save() then refresh()) and, on save, calls appState.saveDayLog(...) which upserts a single DayLog SwiftData row per calendar day (its mere existence marks "reviewed"). Mood tracking is a parallel, optional pipeline layered on top: MoodAIGate (pure booleans), MoodAIAvailability/LiveMoodAIChecker (mirrors FoundationModels' SystemLanguageModel.Availability so nothing else needs to import it) and MoodClassifier (the actual macOS-26-only on-device classification call) are invoked only from the view's .task(id: reflection) debounce loop -- AppState never talks to FoundationModels directly, and a manually-tapped mood always wins a race against a late AI suggestion._

`2 confirmed bugs` · `6 UX issues` · `4 quality notes` · `5 feature ideas`

#### Confirmed bugs

**[MEDIUM] Word-count AI gate never fires for reflections in scripts without whitespace-separated words**  
MoodAIGate.shouldAttemptClassification requires reflection.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count >= 3 (minimumWordCount). For CJK, Thai, and other scripts that don't use spaces between words, an entire substantive sentence splits into a single token, so the word count is always 0 or 1 and the gate never passes -- directly contradicting MoodClassifier's own system prompt, which claims "The reflection may be written in any language."  
> **Failure scenario:** A user writes a genuine, detailed reflection entirely in Japanese with no spaces, e.g. "今日は仕事でとても疲れて、家に帰ってすぐ寝てしまった". shouldAttemptClassification computes wordCount == 1 (no whitespace anywhere in the string), 1 >= 3 is false, and AI mood suggestion never runs for this user no matter how long or emotionally clear their reflection is -- with no error, no message, and no way to know why (moodChecker.availability still reports .available).  
`Sources/DayBarCore/Mood/MoodAIGate.swift:21`

**[MEDIUM] Finishing before AI classification resolves permanently forfeits the suggestion for that day**  
Clicking "Finish review" calls appState.saveDayLog(reflection:, moodTag: selectedMood, moodSource: moodSource) synchronously and dismisses immediately, regardless of whether the .task(id: reflection) debounce/classification is still in flight (up to ~3.6s after the last keystroke). Because a DayLog now exists, MoodAIGate.shouldAttemptClassification's alreadyReviewed gate permanently blocks re-classification on any future open of the same day's review unless the user manually edits the reflection text again to force a new debounce.  
> **Failure scenario:** User types a 5-word reflection ("Long day but got through it"), which is enough to pass the word-count gate, then immediately clicks "Finish review" with the mouse (0.5-1s after their last keystroke, well within the 600ms debounce + up-to-3s classification window). The sheet dismisses with moodTag: nil / moodSource: .none saved. Reopening "Review day..." later shows isExistingReview = true, so the AI suggestion is never retried -- the only way to get a mood logged for that day is to now pick one manually.  
`Sources/DayBar/EndOfDayReviewView.swift:87`

#### UX issues

- **[LOW] "All clear" congratulatory copy fires for empty days too** — `Sources/DayBar/EndOfDayReviewView.swift`  
  When unfinished and openHabits are both empty, the view always shows "All clear -- nice work. 🎉" (lines 59-60), directly under "0/0 tasks done today" (line 37). This exact same celebratory message appears whether the user completed every planned task, or the day simply had zero todos and zero habits ever planned (e.g. opening "Review day..." on a day nothing was scheduled). There is no distinction between "you accomplished everything" and "there was nothing to accomplish."
- **[LOW] No feedback while AI mood classification is running** — `Sources/DayBar/EndOfDayReviewView.swift`  
  After a >=3-word reflection is typed, suggestMoodIfEligible waits 600ms (debounce) then up to 3s (classifyMoodWithTimeout) before a mood tag lights up on its own. Nothing in moodSection shows a spinner or any "thinking" state during that up-to-3.6s window, so a user has no way to know a suggestion is coming versus the feature being off/broken, and nothing invites them to wait for it before hitting Finish.
- **[LOW] No way to clear an accidental mood selection** — `Sources/DayBar/EndOfDayReviewView.swift`  
  moodButton's action always sets `selectedMood = tag; moodSource = .manual` -- tapping an already-selected tag doesn't deselect it, and there is no control to return to "no mood" (MoodSource.none). A mis-tap can only be corrected by choosing a different (also wrong) tag, not by clearing it.
- **[MEDIUM] Icon-only toggle buttons lack VoiceOver labels, unlike the rest of the app** — `Sources/DayBar/EndOfDayReviewView.swift`  
  The habit-open toggle (Image(systemName: "circle"), lines 49-51) and the todo-complete toggle (Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle"), lines 181-184) carry no .accessibilityLabel. VoiceOver will announce something generic like "circle, button" for every row with no indication of which task/habit it acts on. This is an established, working pattern elsewhere in the app -- LofiRadioStrip.swift:120 explicitly labels its icon button ".accessibilityLabel(radio.isPlaying ? "Pause radio" : "Play radio")" -- so this view is inconsistent with the app's own convention.
- **[MEDIUM] Auto-prompt never fires on habit-only days** — `Sources/DayBarCore/Review/EndOfDayReviewGate.swift`  
  EndOfDayReviewGate.shouldPresent gates solely on totalTodayCount > 0 (line 19); totalHabitsTodayCount is never consulted. A user who plans zero todos on a given day but has several open habits will never get the automatic evening nudge, even though the review sheet itself devotes a whole "OPEN HABITS" section (lines 45-57) to exactly that case. Such users must remember to open "Review day..." manually every time.
- **[LOW] Reopened-review header copy doesn't change** — `Sources/DayBar/EndOfDayReviewView.swift`  
  The header always reads "Did you finish what you planned?" (line 28), a forward-looking question, even when isExistingReview is true and the user is really re-opening/editing a review they already finished earlier that evening -- the copy gives no indication the sheet is showing saved data rather than a fresh prompt.

#### Code quality & maintainability

- **MoodClassifier's tag list is a hand-duplicated string, not derived from MoodTag.allCases** — `Sources/DayBarCore/Mood/MoodClassifier.swift`  
  The @Guide(description:) on Classification.tag hardcodes "One of: lovestruck, proud, happy, productive, social, neutral, busyMeetings, tired, anxious, stressed, disappointed" as a doc string, separate from MoodTag's own case list. Adding, removing, or renaming a MoodTag case requires remembering to update this string too, or the model will silently never suggest the new/renamed tag (falling back to .neutral per line 27's `?? .neutral`). Consider a test that asserts the doc string's tag names match MoodTag.allCases.map(\rawValue) so drift is caught in CI.
- **Redundant isNewline check and word-based (not language-agnostic) reflection gate** — `Sources/DayBarCore/Mood/MoodAIGate.swift`  
  MoodAIGate's split predicate `{ $0.isWhitespace || $0.isNewline }` is redundant since Character.isWhitespace already returns true for newlines in Swift. More substantively (see the corresponding bug), a whitespace-word-count heuristic isn't a reliable "is this reflection substantive" signal across languages; a trimmed-character-count threshold would be more locale-robust.
- **AI debounce/timeout/cancellation orchestration lives untested inside the view** — `Sources/DayBar/EndOfDayReviewView.swift`  
  suggestMoodIfEligible's actual sequencing (600ms sleep, 3s classification race, Task.isCancelled recheck) is only exercised indirectly through the pure MoodAIGate booleans in MoodAvailabilityTests -- there's no test coverage for the orchestration itself (e.g. that a superseding keystroke really does cancel an in-flight classification before it applies). Extracting the sequencing into a small, injectable coordinator type would let this be covered without SwiftUI or a real device.
- **onAppear's dayLog(for:) failure is silently swallowed** — `Sources/DayBar/EndOfDayReviewView.swift`  
  `(try? appState.store.dayLog(for: .now)) ?? nil` drops any SwiftData fetch error with no logging; consistent with the rest of the codebase's try?-heavy style, but worth a shared logging shim so a genuine on-disk store problem on this specific screen (which decides whether today counts as reviewed) isn't completely invisible during support/debugging.

#### Feature ideas

- **Local draft autosave for the reflection** — Periodically (or on sheet dismissal via any path) persist the in-progress reflection text and mood pick to a lightweight local draft (UserDefaults or a scratch DayLog field), and restore it the next time the review opens for that day. This would directly neutralize the outside-click data-loss bug while staying fully local and silent -- no popup, no confirmation, just quietly picking back up where the user left off.  
  _Why:_ Fits the calm/local-first philosophy: recovers from interruption without nagging, and requires no new UI.
- **Manual "re-suggest mood" affordance for reopened reviews** — A small, quiet button (only shown when isExistingReview is true and AI is available) that lets the user explicitly re-trigger MoodClassifier against the current reflection text, rather than requiring them to edit the text to accidentally retrigger it. Resolves the documented future-work note already left in MoodAIGate.swift's doc comment.  
  _Why:_ Keeps the existing "never silently overwrite a saved mood" guarantee while giving users an opt-in way to get the suggestion they missed (e.g. by finishing before classification resolved).
- **Gentle weekly mood recap card in Analytics** — A once-a-week, passive summary in AnalyticsView built on the existing MoodAnalytics.buckets infrastructure -- e.g. "This week trended calmer than last week" -- shown only when the Analytics view is opened, never pushed as a notification.  
  _Why:_ Reuses already-tested aggregation code, stays local-only, and surfaces mood trends without gamification or streak pressure.
- **Toggle-to-clear mood selection** — Let tapping an already-selected mood tag deselect it back to MoodSource.none, instead of only ever swapping between tags.  
  _Why:_ Small, low-risk fix for the "no way to back out of a mis-tap" UX gap, consistent with the calm/non-committal tone of the rest of the ritual.
- **Soft, read-only local pattern surfacing** — Entirely local correlation notes surfaced gently in Analytics, e.g. "you tend to log 'tired' after days with fewer completed habits" -- computed from existing DayLog/HabitLog data, shown as a quiet one-liner rather than a chart or score.  
  _Why:_ Adds insight value without cloud dependency, streak-shaming, or loud notifications, matching the stated "calm by default" design philosophy.

---

### Apple Reminders Sync

_RemindersAdapter (@MainActor) wraps EventKit's EKEventStore/EKReminder API behind the ExternalSourceProvider protocol, translating everything into the plain Sendable ReminderDTO/HabitReminderDTO so EventKit never leaks into sync logic or tests (MockRemindersProvider implements the same protocol for testing). RemindersSyncEngine owns two-way reconciliation for regular todos: AppState.refresh() coalesces calls to reconcileIfNeeded() (throttled to 60s unless forced) which first flushes an in-memory pushQueue of locally-dirtied DailyTodo IDs via provider.apply(), then pulls incomplete reminders from the selected calendars and uses ReminderMapping (pure functions) to create/update DailyTodo rows in the shared SwiftData DataStore, with per-row conflict resolution keyed on externalModifiedAt vs. EventKit's lastModifiedDate. AppState's todo intents (advanceTodo/toggleComplete/delay/reschedule/drop/rename) call markRemindersTodoLocallyModified + remindersSync.enqueuePush() to queue outgoing changes asynchronously rather than writing to EventKit synchronously. A sibling HabitRemindersSyncEngine (out of scope here) reuses the same ExternalSourceProvider instance for recurring habit reminders, so both share one EventKit connection and one throttled MainActor sync scheduler exposed to SwiftUI via AppState.isRemindersSyncing/remindersLastSyncedAt/remindersLastSyncError._

`3 confirmed bugs` · `7 UX issues` · `5 quality notes` · `6 feature ideas`

#### Confirmed bugs

**[HIGH] Pending pushes are lost forever if the app quits before the push Task completes, with no error and no retry**  
RemindersSyncEngine.pushQueue is an in-memory `Set<UUID>` (line 9), never persisted. AppState.markRemindersTodoLocallyModified stamps `todo.externalModifiedAt = now` synchronously at the moment of the local edit (Sources/DayBarCore/State/AppState.swift lines 133-137), before the corresponding push to EventKit has actually run or succeeded. If the process ends (quit, crash, sleep) before the async reconcile Task drains pushQueue, the queue is discarded on relaunch and nothing ever re-adds that todo to it, because enqueuePush is only called from the original user-intent call sites.  
> **Failure scenario:** A user with 'Sync with Reminders' enabled completes a reminders-sourced task via toggleComplete, then immediately quits DayBar (or the Mac sleeps) before the coalesced sync Task finishes pushing. On relaunch, the task still shows completed in DayBar (SwiftData persisted the write), but because externalModifiedAt was already optimistically stamped to the edit time, the next pull's shouldApplyRemote(dto, over: existing) comparison (remote.modifiedAt older than todo.externalModifiedAt) returns false, so the stale-incomplete remote reminder is never re-applied over the local state — but the push itself is also never retried. The task permanently shows complete in DayBar while remaining incomplete in Apple Reminders (and on the user's other Apple devices via iCloud), with no lastSyncError ever set and no way for the user to discover or fix the divergence.  
`Sources/DayBarCore/External/RemindersSyncEngine.swift:9`

**[MEDIUM] Every push of a reminders-synced todo silently overwrites the reminder's EventKit priority, including from 'none' to an explicit 'medium'**  
RemindersAdapter.apply() unconditionally sets `reminder.priority = ReminderMapping.eventKitPriority(from: dto.priority)` on every push, regardless of whether priority was actually changed in DayBar. Priority (Model/Enums.swift) only has low/medium/high — there is no 'none' case — and ReminderMapping.priority(fromEventKit:) maps EventKit's 0 ('no priority') into the `default: return .medium` branch. eventKitPriority(from: .medium) always writes back explicit priority 5.  
> **Failure scenario:** User creates a reminder in Apple Reminders with priority set to 'None' (EventKit priority 0). DayBar pulls it in; ReminderMapping maps it to Priority.medium since 'none' can't be represented. User later completes, renames, or drops that task inside DayBar (any action that calls remindersSync.enqueuePush). The resulting push writes reminder.priority = 5 ('Medium') back to the original reminder in Apple's own Reminders app — a priority the user never set and never saw represented anywhere in DayBar's UI — and this change propagates to the user's other Apple devices via iCloud.  
`Sources/DayBarCore/External/RemindersAdapter.swift:110`

**[MEDIUM] Reconciling mirrors that fell out of the incomplete-pull set can blank a task's title**  
pull() only inserts a dto's externalIdentifier into `seen` for entries whose title is non-empty (`for dto in incoming where !dto.title.isEmpty`). Any reminder with a currently-blank title is skipped from `seen` even though it is still incomplete and not deleted. reconcileMirrorsOffPullSet() then treats it as 'missing from the pull set' and calls provider.fetchReminder(externalIdentifier:), which has no title filter, and — since the reminder was just edited (so its lastModifiedDate is newer) — shouldApplyRemote returns true and ReminderMapping.apply() overwrites the local DailyTodo's title with the empty string.  
> **Failure scenario:** A user is mid-edit on a synced reminder in the Reminders app: they select-all and delete the title text, planning to retype it, but pause for a few seconds. If DayBar's periodic sync (throttled to once per 60s while the app is active) happens to run in that window, the reminder's now-blank title is not added to `seen` (line 160 filters it out of the normal pull), but reconcileMirrorsOffPullSet still re-fetches it directly and — since it's unmodified since last local write on DayBar's side would compare newer — applies the blank title onto the local DailyTodo mirror, visibly clearing the task's name in DayBar even though the user never intended to save an empty title.  
`Sources/DayBarCore/External/RemindersSyncEngine.swift:160`

#### Plausible, unverified

**[HIGH] originalPlannedDate never advances forward, causing spurious 'aging/escalation' when a synced reminder's due date moves later** _(uncertain — could not be fully verified either way)_  
ReminderMapping.apply() only lets originalPlannedDate move earlier: `if todo.originalPlannedDate > planned { todo.originalPlannedDate = planned }`. It is never bumped forward when the remote due date moves to a future day. Since DailyTodo.escalationTier()/carryOverAgeInDays() compute age purely from originalPlannedDate vs. now (Model/DailyTodo.swift lines 89-101), and EscalationModel.gentle treats age >= 3 days as the worst '.aging' tier, a task that was carried over for days and then rescheduled forward in Apple Reminders keeps its old originalPlannedDate. Also note apply()'s if/else-if chain (lines 33-41) has no final else: when dto.isCompleted is false and todo.status is .planned/.carriedOver/.snoozed (the common cases), none of the branches fire, so status is left stale even though plannedForDate was just moved.  
> **Failure scenario:** A reminder mirrored into DayBar sits carried-over for 5 days (status becomes .carriedOver via daily rollover, originalPlannedDate stays at day 0). User reschedules the underlying reminder's due date to 2 weeks out in Apple Reminders (meaning 'not now'). Next pull: plannedForDate jumps to the future so the task correctly disappears from today's/overdue lists, but originalPlannedDate is left at day 0 and status is left at .carriedOver. Two weeks later, when that day arrives and the task appears in today's list again, carryOverAgeInDays computes ~19 days old, so escalationTier immediately returns .aging (the most severe tier) on the very first day it's shown — the task looks maximally overdue the instant it reappears, directly contradicting the 'calm by default, never a wall of red' design goal.  
`Sources/DayBarCore/External/ReminderMapping.swift:26`

#### UX issues

- **[MEDIUM] Disabling sync leaves mirrored tasks silently orphaned with no warning** — `Sources/DayBar/RemindersSettingsSection.swift`  
  Toggling 'Sync with Reminders' off just sets Preferences.remindersSyncEnabled = false, which makes reconcileIfNeeded() short-circuit immediately (guard Preferences.remindersSyncEnabled else return false). Any DailyTodo rows with source == .reminders remain in the SwiftData store forever, no longer pulled or pushed, but there is zero copy warning the user this will happen before they flip the toggle off.
- **[LOW] 'Access denied' copy is shown identically for denied and restricted, and for writeOnly** — `Sources/DayBar/RemindersSettingsSection.swift`  
  accessStatusRow shows the same 'Reminders access denied. Enable it in System Settings…' text for both .denied and .restricted. RemindersAdapter also collapses EventKit's .writeOnly authorization into .denied. A managed/parental-controls (.restricted) user often cannot fix this in System Settings at all, and a .writeOnly user actually already granted some access — telling them access was 'denied' is inaccurate and will confuse them ('but I did allow it').
- **[LOW] Raw technical error text surfaces to the user, breaking the app's calm/friendly voice** — `Sources/DayBar/RemindersSettingsSection.swift`  
  The orange error Text simply renders appState.remindersLastSyncError, which is `error.localizedDescription` piped straight through from EventKit NSErrors or from RemindersProviderError.reminderNotFound(id), where id is EventKit's opaque calendarItemIdentifier (e.g. 'Reminder not found: 018E....:EK1'). This is the only place in the reviewed subsystem where raw system/debug strings reach end-user UI, inconsistent with the rest of the app's plain-language copy.
- **[MEDIUM] 'No reminder lists found' is shown even when list loading actually failed** — `Sources/DayBar/RemindersSettingsSection.swift`  
  loadLists() calls appState.remindersSync.fetchLists() directly; on failure the engine sets its own lastSyncError and returns [], but that error is never copied into appState.remindersLastSyncError (which is only refreshed inside runRemindersSync's defer block). The Settings section then renders 'No reminder lists found.' — a plain empty state — even though the real cause was a fetch failure, misleading the user into thinking they have zero Reminders lists.
- **[LOW] Consequential one-way-sync caveats look identical to routine status text** — `Sources/DayBar/RemindersSettingsSection.swift`  
  'Dropping a synced task marks it completed in Reminders.' and 'Skipping a habit in DayBar won't update Reminders.' are both rendered with the same .font(.caption).foregroundStyle(.secondary) styling as the mundane 'Last synced HH:mm' timestamp line. There is no visual weight (icon, color, ordering) distinguishing genuinely surprising behavior from routine status, so users skimming the section are likely to miss the caveats that actually matter.
- **[LOW] Reminder lists are indistinguishable when names collide across accounts** — `Sources/DayBar/RemindersSettingsSection.swift`  
  Each list Toggle only shows list.title (ForEach(lists) { Toggle(list.title, ...) }), and ReminderListDTO carries only calendarIdentifier/title — no account or source. A user with two lists named 'Personal' (e.g. one iCloud, one Exchange) cannot tell which one they are enabling for sync.
- **[LOW] 'Default list' / 'Default habit list' pickers can silently fail to appear** — `Sources/DayBar/RemindersSettingsSection.swift`  
  The push-destination Picker only renders when `pushNewTodos, !lists.isEmpty` (and similarly for habits). A user who enables 'Also add new tasks to Reminders' before loadLists() resolves — or when it silently fails per the empty-state bug above — sees no picker and no indication that one is supposed to be there or is still loading.

#### Code quality & maintainability

- **Undated-reminder fetch pulls the entire calendar history, not just incomplete items** — `Sources/DayBarCore/External/RemindersAdapter.swift`  
  RemindersAdapter.fetchIncomplete's includeUndated branch calls `eventStore.predicateForReminders(in: calendars)`, which returns every reminder (completed and incomplete, across all time) in the selected lists, then filters client-side for `!reminder.isCompleted && reminder.dueDateComponents == nil`. Using `predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)` instead would let EventKit exclude completed reminders server-side, shrinking the fetch as completed history accumulates in a long-lived list.
- **Failing push items retry forever with no backoff or give-up** — `Sources/DayBarCore/External/RemindersSyncEngine.swift`  
  processPushQueue() re-inserts a failed todo's id into pushQueue unconditionally on every failure (`pushQueue.insert(todo.id)`), with no retry count, backoff, or eventual give-up. A permanently-broken item (e.g. stale externalIdentifier) is retried on every single reconcile cycle indefinitely, generating EventKit calls and keeping lastSyncError populated even when nothing new is wrong.
- **lastSyncError is one shared string across unrelated failure sources** — `Sources/DayBarCore/External/RemindersSyncEngine.swift`  
  requestAccess, fetchLists, processPushQueue, pull, and reconcileMirrorsOffPullSet all write into the same `lastSyncError` string, and AppState further concatenates it with habitRemindersSync's own error via '; '. Callers can't tell which operation or which specific todo failed. A typed error (or a per-todo failure flag) would let the UI say something more specific than one global banner.
- **Settings view's loadLists() failure doesn't reach the property the view actually reads** — `Sources/DayBar/RemindersSettingsSection.swift`  
  RemindersSettingsSection.loadLists() calls appState.remindersSync.fetchLists() directly, bypassing AppState.remindersLastSyncError (which is only refreshed by runRemindersSync's defer block). Routing list-loading failures through the same AppState-owned error property (or triggering a real sync cycle) would let the existing orange error Text correctly reflect a failed list load instead of the misleading 'No reminder lists found.' empty state.
- **pushQueue's in-memory-only nature is the root cause of a real data-loss bug** — `Sources/DayBarCore/External/RemindersSyncEngine.swift`  
  As noted in bugs, persisting pending-push todo IDs (e.g. a `pendingPush: Bool` column on DailyTodo, or a small durable queue table) rather than keeping them only in a `Set<UUID>` in RAM would let a relaunch resume interrupted pushes instead of silently forgetting them.

#### Feature ideas

- **Quiet sync-queue indicator** — A small, calm label or dot (e.g. in RemindersSettingsSection or the panel footer) showing '2 changes waiting to sync' whenever pushQueue is non-empty, so a pending local edit that hasn't reached Reminders yet is visible instead of invisible.  
  _Why:_ Directly addresses the current invisibility of pending pushes (see bugs) without any alarming color or popup — just an honest, low-key status line consistent with the app's calm philosophy.
- **Preview before first enabling sync** — When a user flips 'Sync with Reminders' on for the first time, show a short read-only summary ('This will import 12 incomplete reminders from Personal, Work') before anything is written to today's plan.  
  _Why:_ Avoids a surprise flood of unfamiliar tasks landing in the day's list the moment sync is enabled — keeps the first-run experience gentle and predictable, matching the 'plan today's tasks each morning' ritual.
- **Per-list pull-only mode** — Let a specific selected Reminders list be marked 'read from, never write to' (e.g. a shared/family list), so DayBar can show its items without ever pushing local completions/edits back into a list the user doesn't own outright.  
  _Why:_ Local-first, no cloud dependency, and avoids the priority/title-overwrite risks identified above for lists the user doesn't fully control.
- **Gentle 'kept your change' conflict note** — When shouldApplyRemote() decides local wins over a concurrent remote edit, surface a small dismissible inline note on that task row ('kept your edit over a change in Reminders') instead of silently discarding the remote edit.  
  _Why:_ Makes the existing last-write-wins conflict resolution honest and visible without an interrupting dialog — fits 'gentle, escalating, never a wall of red.'
- **Opt out of pushing priority** — A toggle so users who rely on Apple Reminders' own priority flags for other purposes can prevent DayBar from ever writing priority back on push.  
  _Why:_ Directly closes the silent none-to-medium priority-stamping bug found in this audit, as a user-facing safety valve rather than just a code fix.
- **Link an existing local task to a reminder after the fact** — A 'Link to Reminders…' action on an already-created local-only DailyTodo, letting the user opt a pre-existing task into two-way sync instead of only brand-new or pulled items being syncable.  
  _Why:_ Extends the existing sync model without any cloud component, staying purely local/EventKit-based, and removes an arbitrary limitation (only new-at-creation todos can become reminders-sourced).

---

### Lofi Radio (SomaFM)

_RadioPlayerManager (@MainActor @Observable) wraps a single AVPlayer, drives play/pause/next/prev, and runs its own KVO-based reconnect/backoff state machine; it persists only the "last channel / was playing / has user started" triad to UserDefaults (Preferences.swift), never to SwiftData. SomaFMService (actor) fetches/caches channels.json (24h TTL, in Application Support/DayBar/radio) and resolves each channel's .pls playlist to a stream URL via PLSParser (its own 7-day disk cache); RadioArtworkCache (actor) is a parallel disk cache for channel artwork. AppState owns one RadioPlayerManager and one SomaFMService instance, exposes radioChannels/radioSkipChannels/isRadioLoading/radioLoadError, and is the only bridge LofiRadioStrip (SwiftUI) talks to — the subsystem never touches DataStore/SwiftData. It cross-cuts two other engines purely through AppState: it enforces "one audio source at a time" with TickingSoundPlayer (radio start silences ticking; ticking start pauses radio) and PomodoroEngine (a finished work phase can pause radio via `radioPauseOnFocusEnd`), and it reuses AppState's generic `habitMilestoneMessage` banner slot — otherwise owned by the habit-streak subsystem — to show "Focus ended — music paused."_

`1 confirmed bugs` · `6 UX issues` · `5 quality notes` · `4 feature ideas`

#### Confirmed bugs

**[MEDIUM] Reconnect attempts double-count on a single stream failure, halving the effective retry budget**  
Two independent observers each call `scheduleReconnect()` for what is normally one underlying failure event: the `.status == .failed` KVO handler (`handleItemStatus`, lines 236-247) and the `AVPlayerItemFailedToPlayToEndTime` notification handler (`observeFailure`, lines 221-234). AVFoundation commonly fires both for the same disconnect. `scheduleReconnect()` (lines 249-269) has no debounce: each call increments `reconnectAttempt` and cancels/replaces `reconnectTask`, so two calls for one real failure jump the counter from 0 to 2 instead of 0 to 1, and the earlier-scheduled shorter backoff Task gets cancelled and replaced before it ever fires.  
> **Failure scenario:** A brief Wi-Fi drop causes the AAC stream item to fail; both the KVO `.status` observer and the `AVPlayerItemFailedToPlayToEndTime` notification fire within the same run-loop pass. `scheduleReconnect()` runs twice back-to-back, taking `reconnectAttempt` from 0 straight to 2 and discarding the intended 2s backoff in favor of an 8s one. After only two more real hiccups (not the advertised three, 2/4/8s), `reconnectAttempt >= maxReconnectAttempts` trips and the user sees "Connection lost. Tap play to retry." — the reconnect logic silently gives up roughly twice as fast as its own constants (`maxReconnectAttempts = 3`, `reconnectBackoffs = [2, 4, 8]`) suggest.  
`Sources/DayBarCore/Radio/RadioPlayerManager.swift:249`

#### Plausible, unverified

**[MEDIUM] Persisted "radio was playing" intent is silently dropped if the network isn't up yet at launch, with no later retry** _(uncertain — could not be fully verified either way)_  
`AppState.restoreRadioSession()` (lines 553-556) awaits `loadRadioChannels()` then calls `radio.restoreSession(channels: radioChannels)`. If `loadRadioChannels()` throws (e.g. no network yet), `radioChannels` stays `[]`, so `RadioPlayerManager.restoreSession` (lines 94-107) can't resolve a channel and its final guard `let channel = currentChannel` fails — no play is attempted, and no error surfaces. Nothing else in the app ever re-invokes `restoreSession`/auto-play afterward; the only later trigger (LofiRadioStrip's `.task`, line 36-40) calls `loadRadioChannels()` again but never resumes playback.  
> **Failure scenario:** User quits DayBar while the radio is playing (Preferences.radioWasPlaying=true, radioHasUserStarted=true). They reboot with "Launch DayBar at login" enabled, and DayBar's `applicationDidFinishLaunching` fires `restoreRadioSession()` before Wi-Fi has associated. `loadRadioChannels()` throws, `radioChannels` is empty, `restoreSession(channels: [])` returns without playing anything, and `radioLoadError` is set but never shown because the panel isn't open. Even once Wi-Fi connects and the user later opens the panel (which only calls `loadRadioChannels()`, not `restoreSession()`), the radio stays silent until the user manually presses Play — the persisted "was playing" state is effectively lost for that session.  
`Sources/DayBarCore/State/AppState.swift:553`

#### UX issues

- **[LOW] Reconnect/error copy reuses the app's overdue-task escalation color** — `Sources/DayBar/LofiRadioStrip.swift`  
  "Reconnecting…" text and the load/playback error strings all use `.foregroundStyle(.orange)` (LofiRadioStrip.swift lines 65, 156, 161). That is the exact color the rest of the app deliberately reserves for the "aging/overdue task" escalation tier (TodayView.swift lines 213 and 471; TaskHistoryView.swift line 111). A routine radio network hiccup now visually reads with the same urgency cue as an overdue task, undercutting the app's stated "calm by default, never a wall of red" color language.
- **[MEDIUM] Prev/Next/Retry buttons lack accessibility labels, inconsistent with Play/Pause** — `Sources/DayBar/LofiRadioStrip.swift`  
  The backward/forward/retry buttons (LofiRadioStrip.swift lines 103-110, 122-129, 134-149) only set `.help("Previous station")` / `.help("Next station")` / `.help("Retry")`, relying on the SF Symbol's default accessibility description for VoiceOver (e.g. "backward fill", "arrow clockwise"). The Play/Pause button right next to them (lines 112-120) explicitly sets `.accessibilityLabel("Pause radio"/"Play radio")`. VoiceOver users get three robotic, symbol-derived announcements next to one clear one in the same control row.
- **[LOW] Play button tooltip says "random station" even when resuming a chosen one** — `Sources/DayBar/LofiRadioStrip.swift`  
  `.help(radio.isPlaying ? "Pause" : "Play random station")` (LofiRadioStrip.swift line 119) is static regardless of state. Once any station has ever been selected, tapping Play resumes that exact channel — `toggleRadio()` in AppState.swift lines 537-551 checks `if let channel = radio.currentChannel { await playRadio(channel) }` before ever picking randomly. The tooltip is only accurate on a completely fresh install with nothing yet chosen.
- **[LOW] No in-app volume control for the radio** — `Sources/DayBar/LofiRadioStrip.swift`  
  Neither LofiRadioStrip.swift nor the "Lofi Radio" Settings section (SettingsView.swift lines 106-108, which only has a "Pause music when focus session ends" toggle) exposes any volume control; AVPlayer's volume is never touched in RadioPlayerManager.swift, so the only way to adjust loudness is to leave DayBar and change system/output volume — awkward for a feature explicitly meant to be quiet background ambience.
- **[LOW] Now-playing track and station name truncate with no way to read the full text** — `Sources/DayBar/LofiRadioStrip.swift`  
  The station menu label (LofiRadioStrip.swift lines 82-84) and now-playing subtitle (lines 163-167) are hard `.lineLimit(1)`, with no tooltip/hover/accessibility value exposing the full string, so longer "Artist - Track" metadata or channel titles are silently clipped.
- **[MEDIUM] Playing the radio silently disables Mac idle sleep with no disclosure** — `Sources/DayBarCore/Radio/RadioPlayerManager.swift`  
  `beginActivity()` (RadioPlayerManager.swift lines 291-297) calls `ProcessInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], ...)` for as long as radio plays, and is only released on pause/stop. Nothing in LofiRadioStrip.swift or SettingsView.swift's Lofi Radio section mentions this. Because playback state also auto-resumes on next launch (`Preferences.radioWasPlaying`), a user who leaves the lid open with radio running (e.g. steps away, forgets to pause) will have their Mac never idle-sleep, silently costing battery — a surprising side effect for what is meant to be a light background-ambience feature.

#### Code quality & maintainability

- **RadioArtworkCache / AppState.artworkData(for:) is fully implemented but dead code** — `Sources/DayBarCore/Radio/RadioArtworkCache.swift`  
  RadioArtworkCache.swift implements a complete disk-backed artwork cache (actor, NSImage bridging) and AppState.swift exposes `artworkData(for:)` (lines 558-560) to call it, but no View anywhere (LofiRadioStrip.swift or otherwise) ever calls `artworkData(for:)` or renders channel art. Either wire channel artwork into the station picker/strip, or remove the cache to cut maintenance surface.
- **SomaFMService.channel(withID:) has no callers** — `Sources/DayBarCore/Radio/SomaFMService.swift`  
  `channel(withID:now:)` (SomaFMService.swift lines 69-72) is unused across Sources and Tests. Either delete it or use it where a single-channel lookup by id would simplify existing call sites.
- **Resuming from pause always performs a full cold restart instead of a lightweight resume** — `Sources/DayBarCore/Radio/RadioPlayerManager.swift`  
  `togglePlayPause()` (lines 72-78) calls `play(channel:)` to resume, which goes through `startPlayback` → `startPlayer(with:)` and always builds a brand-new `AVPlayerItem`/`AVPlayer` (lines 171-182), re-resolving the stream URL and re-buffering, even though `pause()` never tears the player down. A simple `player?.play()` when the existing player/item is still valid would resume instantly without the buffering flash on every pause/resume cycle.
- **PLSParser's cache-key sanitization is incomplete** — `Sources/DayBarCore/Radio/PLSParser.swift`  
  `cacheFileURL` (PLSParser.swift lines 50-57) base64-encodes the playlist URL and only replaces `/` with `_`; `+` and `=` are left in the filename. Harmless on APFS today, but fragile if this cache directory is ever zipped/exported/synced. Prefer a URL-safe base64 alphabet or a hash (e.g. SHA-256 hex) as the cache key.
- **RadioPlayerManager — the most stateful class in the subsystem — has zero test coverage** — `Tests/DayBarTests/SomaFMCacheTests.swift`  
  None of Tests/DayBarTests exercise RadioPlayerManager's play/pause/reconnect/backoff state machine, persistence side effects, or the `onPlaybackStarted` hook, despite it containing all the KVO wiring and the reconnect-attempt bug noted above. Similarly, SomaFMService.fetchAllChannels's network-failure-falls-back-to-cache path and PLSParser's `loadCachedStreamURL`/`saveCachedStreamURL` round trip and TTL expiry (the app's actual offline-resilience logic) are untested — SomaFMCacheTests.swift only tests the pure `isCacheFresh` boolean helper, not the file I/O around it.

#### Feature ideas

- **In-panel volume slider** — A small, locally-persisted volume slider (or a scroll gesture on the waveform icon) next to the transport controls in LofiRadioStrip, backed by `AVPlayer.volume`, so users don't have to leave the panel to adjust background-music loudness.  
  _Why:_ Purely local UI state, no cloud/account needed, and directly reduces friction for the app's ambient-listening use case without adding any nudging/gamification.
- **Auto-pause radio after a period of inactivity** — Optional "pause after N minutes of idle" setting for the lofi radio, mirroring the existing `radioPauseOnFocusEnd` toggle, that also releases the `idleSystemSleepDisabled` activity token.  
  _Why:_ Directly addresses the current behavior where leaving radio playing keeps the Mac from idle-sleeping indefinitely; keeps the feature calm and battery-friendly by default rather than requiring the user to remember to pause.
- **Auto-resume radio on break start** — Since a finished work phase can already auto-pause the radio (`radioPauseOnFocusEnd`), let a matching preference auto-resume the last-played station when a break begins, completing a "focus = ticking, break = lofi" rhythm instead of a one-directional pause.  
  _Why:_ Extends an already-built mutual-exclusion mechanism (ticking vs. radio) into a full calm ritual tied to the core Pomodoro flow, with no new infrastructure.
- **Local "pinned stations" shortcut** — Let the user pin 1-3 favorite stations (stored in UserDefaults, no account) to the top of the station Menu, separate from the fixed curated order.  
  _Why:_ Small, local-only personalization that respects the existing curated-list simplicity while cutting down on scrolling through ~15 stations.

---

### Settings, App State & Persistence

_AppState is the single @MainActor @Observable hub: it owns DataStore (a thin SwiftData wrapper) plus RolloverEngine, HabitEngine, PomodoroEngine, NotificationScheduler, and the two Reminders-sync engines, and nearly every user intent (addTodo, advanceTodo, delay, archiveHabitTemplate, ...) follows a "mutate model -> store.save() -> refresh(now:)" pattern that re-runs rollover, reloads today/carried/habit lists, reschedules notifications, and kicks off a debounced/coalesced Reminders-sync Task. SettingsView (plus its HabitsSettingsSection/RemindersSettingsSection children) is a pure @AppStorage front-end over UserDefaults-backed PreferenceKeys/Preferences (typed reads with baked-in fallbacks); most preferences are read live by the engines at the moment they're needed, but a few are pushed back into live state through hand-built "snapshot string" .onChange triggers that call appState.applyPreferences() / notifications.rescheduleRepeating() / refresh(). DataStore wraps one SwiftData ModelContainer (DailyTodo, AppMeta, FocusSession, DayLog, HabitTemplate, HabitLog) behind typed #Predicate query helpers, plus a Codable DTO layer (StoreDTO.swift) used both for the one-time Phase-1 JSON migration and for an already-built-but-unwired JSON export/import path; AppMeta is the single-row idempotency ledger (lastProcessedDay, lastHabitMaterializedDay, didImportLegacyJSON) that RolloverEngine, HabitEngine, and the legacy importer all gate on._

`6 confirmed bugs` · `6 UX issues` · `5 quality notes` · `4 feature ideas`

#### Confirmed bugs

**[HIGH] SwiftData save() failures are silently swallowed everywhere**  
DataStore.save() only prints to the console when context.save() throws; no error is surfaced to AppState or the UI, and no retry occurs. Every intent method in AppState (addTodo, advanceTodo, toggleHabit, saveDayLog, etc.) calls store.save() and assumes success, and SwiftUI continues to render the (already-mutated-in-memory) @Model objects as if the edit succeeded.  
> **Failure scenario:** Disk is full, the container's file is temporarily locked (e.g. a backup tool has it open), or the on-disk store is corrupted after a prior crash. The user adds tasks, completes habits, and writes an end-of-day reflection all evening; every store.save() call throws and is only printed to Console.app. The UI looks completely normal (in-memory objects are mutated) but nothing is persisted. On the next launch the entire evening's work is gone, with no warning ever shown to the user.  
`Sources/DayBarCore/Data/DataStore.swift:33`

**[HIGH] importSnapshot deletes all data before the re-insert is committed, with no rollback on failure**  
importSnapshot deletes every DailyTodo/HabitTemplate/HabitLog and calls save() (committing the deletion), then inserts the new snapshot's rows and calls save() again. If the second save() throws (constraint violation, disk full, crash) between the two calls, the delete is already durable but the re-insert is not.  
> **Failure scenario:** A user-triggered restore of a backup snapshot (the DTO/JSON plumbing already exists and is unit-tested, e.g. PersistenceTests.testImportSnapshotReplacesAll) deletes all existing todos and habits, then the app crashes or the disk fills up before the second save() completes. The user is left with a completely empty database instead of either the old data or the restored data -- silent, total, unrecoverable data loss from what should be a safe restore operation.  
`Sources/DayBarCore/Data/DataStore.swift:306`

**[MEDIUM] Notification-permission warning in Settings can go stale because NotificationScheduler isn't Observable**  
SettingsView reads appState.notifications.authorized to decide whether to show the permission-denied row. NotificationScheduler is a plain @MainActor class (no @Observable), and notifications is a `let` on the @Observable AppState, so mutating notifications.authorized inside refreshAuthorizationStatus()'s async completion handler never triggers a SwiftUI re-render of SettingsView -- Observation only tracks stored-property mutations on @Observable types, and NotificationScheduler doesn't participate.  
> **Failure scenario:** User previously denied notifications; DayBar shows the "Notifications are turned off" row. User grants permission in System Settings, then opens DayBar Settings. .onAppear fires refreshAuthorizationStatus(), which asynchronously flips notifications.authorized to true a moment later -- but because the mutation lives on a non-Observable class, SwiftUI never re-evaluates SettingsView.body, so the stale "turned off" warning (and its Open System Settings button) keeps showing until the user happens to toggle an unrelated @AppStorage-backed control.  
`Sources/DayBar/SettingsView.swift:98`

**[MEDIUM] Toggling a Reminders-synced habit never actually schedules the Reminders push**  
Every other AppState intent (advanceTodo, delay, drop, archiveHabitTemplate, ...) ends with store.save() followed by refresh(now:), and refresh() is what calls scheduleRemindersSync(now:) to launch the coalesced sync Task. toggleHabit is the one exception: it calls store.save(), conditionally calls habitRemindersSync.enqueuePush(for:) and invalidateRemindersSync(), then only calls reloadLists/rebuildHabitCaches -- never refresh() or scheduleRemindersSync().  
> **Failure scenario:** A habit template has Reminders sync enabled. User checks it off in the panel and closes the panel without touching anything else. Because toggleHabit never calls refresh()/scheduleRemindersSync, the enqueued push sits unsent until some unrelated trigger fires a full refresh() (midnight day-change, sleep/wake, an EKEventStoreChanged notification, or the next app launch) -- the completion can lag arbitrarily behind in the actual Reminders app, contradicting the "synced" expectation.  
`Sources/DayBarCore/State/AppState.swift:375`

**[MEDIUM] Turning off the backlog-notification toggle in Settings doesn't cancel an already-scheduled notification**  
SettingsView's notifSnapshot string (used to gate the .onChange that calls appState.refresh(), which is what re-runs notifications.updateBacklogNudge) only includes morningEnabled/Hour/Minute, eveningEnabled/Hour/Minute, and habitNotifyEnabled. Both phaseEndNotify and backlogNotify toggles exist in the same Notifications section but are excluded from the snapshot string, so changing them never triggers .onChange.  
> **Failure scenario:** User has aging carried-over tasks; DayBar already scheduled a 2pm "Tasks piling up" backlog notification (updateBacklogNudge is called from every refresh()). At 1pm the user opens Settings and turns off "Remind me about piled-up tasks", then closes the panel without triggering any other refresh(). Because backlogNotify isn't part of notifSnapshot, no refresh() runs, updateBacklogNudge never re-executes to call removePendingNotificationRequests, and the notification the user just explicitly disabled still fires at 2pm.  
`Sources/DayBar/SettingsView.swift:41`

**[MEDIUM] Launch-at-login registration errors are silently discarded and the toggle snaps back with no explanation**  
SettingsView's .onChange(of: launchAtLogin) calls `try? LaunchAtLogin.setEnabled(newValue)` and then immediately re-reads `launchAtLogin = LaunchAtLogin.isEnabled`. SMAppService.mainApp.register()/unregister() can throw (e.g. rate-limiting after rapid toggling, or transient Login Items daemon errors), and the thrown error is dropped by `try?` with zero user feedback.  
> **Failure scenario:** User flips "Launch DayBar at login" ON; SMAppService.mainApp.register() throws (this is a documented, real-world occurrence when the login-item registration is toggled repeatedly in a short window, e.g. during testing or a quick double-click). The toggle visually snaps back to OFF a moment later because LaunchAtLogin.isEnabled still reports the pre-registration status, and the user gets no message at all explaining why their change didn't take -- indistinguishable from a UI glitch.  
`Sources/DayBar/SettingsView.swift:134`

#### UX issues

- **[MEDIUM] Weekday picker in the habit editor is unreadable to VoiceOver** — `Sources/DayBar/HabitsSettingsSection.swift`  
  The custom-schedule weekday selector renders seven single-letter Buttons labelled S M T W T F S with no accessibility labels or hints. VoiceOver announces each as just "S button" / "T button", so Tuesday and Thursday are indistinguishable, as are Sunday and Saturday.
- **[HIGH] "Archive habit" is a single-click, irreversible action with no confirmation** — `Sources/DayBar/HabitsSettingsSection.swift`  
  HabitEditorSheet's Archive button (role: .destructive) calls appState.archiveHabitTemplate immediately on tap. There is no confirmation dialog, and no code path anywhere in the app ever sets isActive back to true (grep for isActive shows only the archive call site and the model's default), so archiving is permanent. If the habit was Reminders-synced, archiving also enqueues a push that deletes the corresponding external Reminders item, cascading the irreversible action into another app.
- **[MEDIUM] Reminders sync toggle stays visually ON even when access is denied and nothing is syncing** — `Sources/DayBar/RemindersSettingsSection.swift`  
  RemindersSettingsSection's "Sync with Reminders" Toggle is bound directly to the syncEnabled @AppStorage value; turning it on when EventKit access is denied leaves the switch ON while accessStatusRow shows only a small caption underneath. There is no automatic revert of the toggle and no prominent state (e.g. disabled/off) communicating that sync is not actually happening.
- **[MEDIUM] System-controlled settings states never refresh after the user leaves and returns from System Settings** — `Sources/DayBar/SettingsView.swift`  
  Notification authorization (SettingsView.onAppear calls refreshAuthorizationStatus once), Apple Intelligence availability, and Launch-at-Login status are all only checked when the Settings sheet first appears or when the user flips a control in-app. If the user alt-tabs to System Settings to grant/revoke one of these permissions and comes back without fully closing/reopening the sheet, DayBar keeps showing the stale permission row.
- **[LOW] Unrecognized mood-AI unavailability reason renders a blank row** — `Sources/DayBar/SettingsView.swift`  
  moodAvailabilityRow's switch has an explicit case for .unavailable(.other) that renders EmptyView(). If Apple Intelligence is on for the user's account but LiveMoodAIChecker's catch-all maps some SystemLanguageModel.Availability.unavailable reason to .other, the Mood section silently shows nothing at all -- no explanation of why AI mood suggestions never appear even though the toggle is on.
- **[LOW] Nine settings sections crammed into one fixed-size, non-resizable scrolling form** — `Sources/DayBar/SettingsView.swift`  
  SettingsView locks the sheet to .frame(width: 380, height: 680) and stacks Pomodoro, Sound, Notifications, Habits, Apple Reminders, Lofi Radio, Mood, Startup, and Shortcut sections in a single Form with no in-page navigation. Combined with the fixed frame, larger Dynamic Type sizes have nowhere to grow into, so long rows (e.g. "Long break every 4 focus sessions", Reminders list toggles) are likely to clip or wrap awkwardly, and finding a specific toggle requires scrolling through unrelated sections.

#### Code quality & maintainability

- **Replace hand-rolled "snapshot string" .onChange triggers with per-field or Equatable-struct change detection** — `Sources/DayBar/SettingsView.swift`  
  pomodoroSnapshot and notifSnapshot exist purely so a single .onChange can fire when any of several @AppStorage values change. This pattern is exactly what caused the backlogNotify/phaseEndNotify gap above -- adding a new toggle requires remembering to also add it to the string. A small Equatable struct (or several explicit .onChange modifiers) would make omissions a compile-time-visible field rather than a silent string-interpolation gap.
- **De-duplicate the hour/minute <-> Date Binding helper** — `Sources/DayBar/SettingsView.swift`  
  SettingsView.timeBinding(_:_:) and HabitEditorSheet's private timeBinding in HabitsSettingsSection.swift implement identical Calendar.current.date(bySettingHour:minute:...) <-> DateComponents logic. Extracting one shared helper would remove the duplication and the risk of the two drifting.
- **HabitsSettingsSection.reload() reimplements DataStore.activeHabitTemplates() inline** — `Sources/DayBar/HabitsSettingsSection.swift`  
  reload() calls `appState.store.allHabitTemplates().filter(\.isActive)` instead of the existing `store.activeHabitTemplates()` helper that does the same thing. Two independent implementations of "active habit templates" can silently diverge if the definition of active ever changes (e.g. to also exclude paused habits).
- **toggleHabit re-fetches the HabitTemplate from the store instead of reusing the already-loaded cache** — `Sources/DayBarCore/State/AppState.swift`  
  toggleHabit calls `try? store.habitTemplate(id: log.templateId)` to check remindersSyncEnabled, even though the caller-visible todayHabits array (rebuilt on the prior refresh) already pairs each log with its template. This is an avoidable SwiftData fetch on every single habit checkbox tap.
- **Promote DataStore.save()'s failure path beyond a bare print** — `Sources/DayBarCore/Data/DataStore.swift`  
  Given how many user actions funnel through store.save(), even a minimal observable signal (e.g. a lastSaveError timestamp/message on DataStore or AppState) would let the UI eventually show "changes may not be saved" instead of failing completely silently, and would make the underlying data-loss bug flagged above much easier to diagnose in the field.

#### Feature ideas

- **Wire up the existing export/import snapshot machinery to a Settings "Back up / Restore" pair** — DataStore.exportSnapshot()/importSnapshot() plus JSONStore's encode/decode are already implemented and unit-tested but have no UI entry point anywhere in the app. Add a small "Data" section in Settings with "Back up to file..." and "Restore from file..." (NSSavePanel/NSOpenPanel), with a confirmation step before the destructive import.  
  _Why:_ Gives local-first, no-cloud users a genuine safety net without adding any account or network dependency, and it directly derisks the silent-save-failure and non-atomic-import bugs found in this audit by giving users a way to protect themselves.
- **Finish the planned Settings "intensity" control for escalation thresholds** — EscalationModel.swift's own doc comment says "Ships calm; the Settings 'intensity' control can lower these later to nudge harder," but AppState.thresholds is hardcoded to .gentle with no way to change it. Expose 2-3 calm presets (e.g. Gentle / Standard) in Settings that adjust slippedMinDays/agingMinDays.  
  _Why:_ This is a feature the codebase already anticipated and half-built; finishing it lets users who want earlier visual nudging opt in without ever exposing a genuinely alarming preset, staying true to "calm by default, never a wall of red."
- **Small "Data & Sync" status readout in Settings** — Show a quiet line with the local store's last successful save time alongside the existing Reminders "Last synced" text, so a single-user, local-only app still gives some reassurance that data is safe.  
  _Why:_ Matches the calm, non-alarming philosophy -- a small factual status line rather than error dialogs -- while giving visibility into the exact silent-failure class of bug this audit surfaced.
- **One-tap "quiet for today" for reminders** — A single action next to the Notifications section that silences the morning/evening/backlog reminders for the rest of the current day, instead of requiring the user to hunt down and flip several individual toggles.  
  _Why:_ Fits the gentle-escalation philosophy: an easy, temporary, non-punitive way to get a quiet day without permanently reconfiguring notification preferences.

---

## Method

**Build & test:** `xcodebuild test` against the current working tree (including uncommitted changes to the analytics hover, end-of-day review gate, and sound engines) — clean build, 167/167 tests passing. Two Swift 6 strict-concurrency warnings were found this way that no source-reading agent could have caught.

**Review:** 86 independent agents across two runs. Nine subsystem audits each read the relevant source plus its existing tests and produced UX issues, candidate bugs, quality notes, and feature ideas. Every candidate bug rated medium or high severity was then re-investigated by two independent, adversarially-instructed verifiers per bug (told to default to "refuted" unless they could trace the exact failing code path) — a bug is only labeled **confirmed** if both agreed. 5 candidate bugs were refuted this way and dropped; 4 remain genuinely uncertain and are shown as such inside their subsystem section. A final synthesis pass then cross-referenced all nine subsystem reports to find patterns and feature ideas no single subsystem view could see on its own.
