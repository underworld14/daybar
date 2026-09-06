# DayBar Landing-Page Screenshot Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four landing-page placeholder illustrations with polished compositions containing captures of the real DayBar UI while preserving the user's local data.

**Architecture:** Temporarily move the complete live SwiftData directory to a timestamped backup, create an isolated demo store with a throwaway Swift helper linked against `DayBarCore`, and capture real app windows through Computer Use. Compose the raw captures into fixed landing-page canvases, update HTML references, then restore the original directory byte-for-byte by moving it back.

**Tech Stack:** Swift 5, SwiftData, DayBarCore, macOS Computer Use, PNG, Pillow, static HTML/CSS, Beads.

## Global Constraints

- Use the installed Release app at `/Applications/DayBar.app` for every visible capture.
- Keep all visible demo copy fictional and in English.
- Do not expose personal reminders, notes, calendars, names, or desktop content.
- Final canvases are `640 x 720` for `today-panel.png` and `560 x 420` for the other three assets.
- Preserve the user's complete `~/Library/Application Support/DayBar` directory and relaunch it after capture.
- Keep `.env` and `.venv` untouched.

---

### Task 1: Protect the live store and create the demo state

**Files:**
- Create temporarily: `build/ScreenshotSeeder.swift`
- Create temporarily: `build/screenshot-captures/`
- Runtime backup: `~/Library/Application Support/DayBar.capture-backup-20260906/`

**Interfaces:**
- Consumes: the Release `DayBarCore.framework` in `build/DerivedData/Build/Products/Release`
- Produces: a temporary DayBar SwiftData store containing todos, habits, focus sessions, and mood history

- [ ] **Step 1: Record and stop the installed app**

Run:

```bash
pgrep -x DayBar
pkill -TERM -x DayBar
```

Expected: the first command returns one installed DayBar PID and the process is absent after termination.

- [ ] **Step 2: Move the complete live directory to a recoverable backup**

Run only after confirming the exact paths:

```bash
mv -f "$HOME/Library/Application Support/DayBar" "$HOME/Library/Application Support/DayBar.capture-backup-20260906"
mkdir -p "$HOME/Library/Application Support/DayBar"
```

Expected: the backup contains the prior store files and the live path is an empty directory.

- [ ] **Step 3: Create a throwaway seeder**

Create `build/ScreenshotSeeder.swift` with an `@main @MainActor` entry point that:

```swift
import Foundation
import DayBarCore

@main
struct ScreenshotSeeder {
    @MainActor
    static func main() throws {
        let store = DataStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int, hour: Int = 9) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: today)!
            return calendar.date(byAdding: .hour, value: hour, to: base)!
        }

        let todos: [DailyTodo] = [
            DailyTodo(title: "Polish the DayBar landing page", createdDate: day(-2), plannedForDate: today, status: .inProgress, priority: .high, pomodoroCount: 2),
            DailyTodo(title: "Review the launch checklist", createdDate: day(-1), plannedForDate: today, completedDate: day(0, hour: 10), status: .completed, priority: .medium),
            DailyTodo(title: "Send the release notes", createdDate: day(0, hour: 8), plannedForDate: today, status: .planned, priority: .medium),
            DailyTodo(title: "Plan the next product experiment", createdDate: day(0), plannedForDate: day(1), status: .planned, priority: .medium),
            DailyTodo(title: "Reply to design feedback", createdDate: day(-2), plannedForDate: day(-1), originalPlannedDate: day(-1), status: .carriedOver, priority: .medium),
            DailyTodo(title: "Book a quiet focus block", createdDate: day(-4), plannedForDate: day(-3), originalPlannedDate: day(-3), status: .carriedOver, priority: .low),
            DailyTodo(title: "Organize the research notes", createdDate: day(-6), plannedForDate: day(-5), originalPlannedDate: day(-5), status: .carriedOver, priority: .low),
        ]
        todos.forEach { store.insert($0) }

        let stretch = store.insert(HabitTemplate(title: "Morning stretch", cueText: "After the first glass of water", symbolName: "figure.cooldown", sortOrder: 0))
        let reading = store.insert(HabitTemplate(title: "Read for 20 minutes", cueText: "Before opening messages", symbolName: "book", sortOrder: 1))
        for offset in -13...0 {
            let date = day(offset)
            store.insert(HabitLog(templateId: stretch.id, day: date, completedAt: date, status: .completed))
            let readingDone = offset != -4 && offset != 0
            store.insert(HabitLog(templateId: reading.id, day: date, completedAt: readingDone ? date : nil, status: readingDone ? .completed : .pending))
        }
        for offset in -13...0 where offset != -4 {
            for session in 0..<(abs(offset) % 3 + 1) {
                store.insert(FocusSession(endedAt: day(offset, hour: 11 + session), minutes: 25, completed: true))
            }
        }
        for offset in -6 ..< 0 {
            _ = store.upsertDayLog(day: day(offset), reflection: "Made steady progress and protected time for the important work.", plannedCount: 4, completedCount: 3, moodTag: offset == -2 ? .tired : .productive, moodSource: .manual)
        }
        guard store.save() else { fatalError(store.lastSaveError ?? "Failed to save demo data") }
    }
}
```

- [ ] **Step 4: Compile and execute the seeder**

Run:

```bash
xcrun swiftc build/ScreenshotSeeder.swift \
  -F build/DerivedData/Build/Products/Release \
  -I build/DerivedData/Build/Products/Release \
  -framework DayBarCore -framework SwiftData \
  -o build/screenshot-seeder
DAYBAR_FRAMEWORKS="$PWD/build/DerivedData/Build/Products/Release"
DYLD_FRAMEWORK_PATH="$DAYBAR_FRAMEWORKS" build/screenshot-seeder
```

Expected: exit code `0` and a new `daybar.store` exists in the live DayBar directory.

- [ ] **Step 5: Launch the installed app and verify fictional content only**

Run:

```bash
open -n /Applications/DayBar.app
```

Expected: exactly one DayBar process from `/Applications/DayBar.app`.

### Task 2: Capture four authentic UI states

**Files:**
- Create temporarily: `build/screenshot-captures/today-panel-raw.png`
- Create temporarily: `build/screenshot-captures/carry-over-raw.png`
- Create temporarily: `build/screenshot-captures/dayscape-focus-raw.png`
- Create temporarily: `build/screenshot-captures/end-of-day-review-raw.png`

**Interfaces:**
- Consumes: the running installed app with the demo store from Task 1
- Produces: Retina PNG captures containing only DayBar windows

- [ ] **Step 1: Open the Today panel and capture the complete native panel**

Use Computer Use to invoke the DayBar quick-add shortcut, inspect the accessibility tree, and capture the visible panel. Save the returned screenshot to `build/screenshot-captures/today-panel-raw.png`.

Expected: habits, active and completed todos, tomorrow, carry-over, Dayscape, radio, and focus controls are visible; the menu bar, notch, wallpaper, and cursor are excluded.

- [ ] **Step 2: Capture a carry-over-focused panel state**

Scroll the native panel so the `CARRIED OVER` section and its `1 day`, `3 days`, and `5 days` aging pills are all legible, then capture `carry-over-raw.png`.

Expected: all visible content remains real DayBar UI and no user data is present.

- [ ] **Step 3: Capture Dayscape and focus streak**

Open `Menu > Statistics…`, retain the `Tasks` and `Day` selections, and capture the top of the Statistics sheet as `dayscape-focus-raw.png`.

Expected: focus streak, seven-day Dayscape, completion summary, and focus metrics are legible.

- [ ] **Step 4: Capture end-of-day review**

Close Statistics, choose `Menu > Review day…`, enter `Shipped the important work; tomorrow already feels lighter.`, select `Productive`, and capture `end-of-day-review-raw.png` without pressing `Finish review`.

Expected: the sheet shows open tasks, the fictional reflection, and the selected mood.

### Task 3: Compose and wire the landing-page assets

**Files:**
- Create: `site/assets/screenshots/today-panel.png`
- Create: `site/assets/screenshots/carry-over.png`
- Create: `site/assets/screenshots/dayscape-focus.png`
- Create: `site/assets/screenshots/end-of-day-review.png`
- Modify: `site/index.html`
- Delete: `site/assets/screenshots/today-panel.svg`
- Delete: `site/assets/screenshots/carry-over.svg`
- Delete: `site/assets/screenshots/dayscape-focus.svg`
- Delete: `site/assets/screenshots/end-of-day-review.svg`

**Interfaces:**
- Consumes: the four raw captures from Task 2
- Produces: final fixed-size PNG files referenced by the landing page

- [ ] **Step 1: Compose each capture**

Use Pillow to place each native capture proportionally on an RGB `#EEF0F7` canvas, with 28-48 px breathing room and a subtle shadow (`black`, blur radius `18`, opacity `30`). Preserve the captured UI pixels without repainting controls. Save optimized PNG files at the exact dimensions in Global Constraints.

- [ ] **Step 2: Visually inspect all four final PNGs**

Open each asset at original resolution. Verify no crop cuts through text or controls, no personal desktop content remains, typography is readable, and the compositions share the same background treatment.

- [ ] **Step 3: Update landing-page image references and alt text**

Change each `.svg` source in `site/index.html` to the matching `.png`. Replace illustrative-placeholder alt text with factual descriptions of the actual captured UI state.

- [ ] **Step 4: Remove the obsolete placeholder SVGs**

Delete only the four exact SVG files listed in this task.

- [ ] **Step 5: Validate and commit the landing asset change**

Run:

```bash
rg -n "PLACEHOLDER|Illustrative mockup|screenshots/.*\.svg" site
python3 -m http.server 8765 --directory site
git diff --check
```

Expected: the search returns no matches, the four images load over the local static server, and `git diff --check` exits `0`.

Commit:

```bash
git add site/index.html site/assets/screenshots
git commit -m "Replace landing placeholders with DayBar screenshots"
```

### Task 4: Restore user data and complete verification

**Files:**
- Runtime restore: `~/Library/Application Support/DayBar/`
- Update tracker: `.beads/issues.jsonl`

**Interfaces:**
- Consumes: the backup directory from Task 1 and final assets from Task 3
- Produces: the user's original running DayBar state and a clean, pushed repository change

- [ ] **Step 1: Stop DayBar and move the demo directory to Trash**

Run after resolving the exact paths:

```bash
pkill -TERM -x DayBar
mv -f "$HOME/Library/Application Support/DayBar" "$HOME/.Trash/DayBar-screenshot-demo-20260906"
```

Expected: the demo store remains recoverable in Trash.

- [ ] **Step 2: Restore the original directory and relaunch**

Run:

```bash
mv -f "$HOME/Library/Application Support/DayBar.capture-backup-20260906" "$HOME/Library/Application Support/DayBar"
open -n /Applications/DayBar.app
```

Expected: one installed DayBar process starts and the original data is visible.

- [ ] **Step 3: Run final asset and repository checks**

Run:

```bash
file site/assets/screenshots/*.png
rg -n "PLACEHOLDER|Illustrative mockup|screenshots/.*\.svg" site
git diff --check
git status --short --branch
```

Expected: four valid PNG files, no placeholder references, no whitespace errors, and only intended changes plus the pre-existing `.env` and `.venv` entries.

- [ ] **Step 4: Close the Beads issue and push both stores**

Run:

```bash
bd close daybar-l84 --reason="Captured and shipped four real DayBar landing-page assets; restored the original local store."
bd dolt push
git pull --rebase
git push
git status --short --branch
```

Expected: `main` is up to date with `origin/main`, the Beads task is closed, and all intended commits are pushed.
