# Board Enrichments: Custom Date, Markdown Description, Checklist Click Fix

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tasks can be created for any date from the board (list/kanban), task descriptions render Trello-style markdown with an edit/preview toggle, and checklist rows in the detail sheet respond to clicks again.

**Architecture:** All three changes converge on two files: `TaskBoardView.swift` (composer + row/card chips) and `TodoDetailSheet.swift` (planned-date picker, markdown description, checklist fix). Core already supports arbitrary planned dates (`AppState.addTodo(plannedFor:)` normalizes via `DayMath.startOfDay`); the custom-date work is UI-only plus one new core mutator (`setPlannedDate`) that does not resurrect completed tasks. Markdown rendering uses the `MarkdownUI` SPM package; raw markdown stays in `notes` (backward compatible, Reminders sync keeps pushing plain text).

**Tech Stack:** SwiftUI (macOS 14 target), SwiftData, XCTest, XcodeGen (`project.yml`), MarkdownUI 2.x.

**Spec:** Conversation 2026-10-11: (1) custom date on task creation in board list/kanban, (2) richer Trello-like description (full markdown renderer chosen), (3) checklist in detail sheet not clickable. bd issues: `daybar-t07` (checklist bug), `daybar-xeb` (custom date), `daybar-b8s` (markdown description).

## Global Constraints

- macOS deployment target 14.0 (`project.yml`); do not raise it.
- Run `xcodegen generate` after any `project.yml` change, before building.
- Tests follow `BoardStatusTests` conventions: XCTest, `@MainActor`, `DataStore(inMemory: true)`, fixed `now = Date(timeIntervalSince1970: 2_000_000_000)`, Gregorian calendar pinned to GMT.
- No third-party dependency other than MarkdownUI.
- Task tracking via `bd` only; close the issue as each task lands.
- TodoDetailSheet is shared by the tray panel (TodayView), main window (TaskBoardView), and history (TaskHistoryView) — changes must work in all three surfaces.

## Review Focus

1. **Completed task + date edit** — changing the planned date of a completed task must not clear `completedDate` or flip status; the task must stay in Done. Pinned by `testSetPlannedDatePreservesCompletedTask` (Task 2).
2. **Past-dated new task** — creating a task with a past custom date must NOT appear in Today; it becomes carried-over/overdue per existing queries. Pinned by `testSetPlannedDateNormalizesToStartOfDay` + manual smoke in All Tasks scope.
3. **Legacy notes text** — old plain-text notes containing `#`, `*`, `[` must render in preview without crashing or mangling; raw text is still what's stored and synced. Pinned by `testAutolinkedLeavesMarkdownLinksAlone` + manual smoke with `# not a heading * star [ bracket`.
4. **Tray panel sheet** — checklist fix must be verified in the tray panel sheet (TodayView), not only the main window sheet; the two run in different NSWindow/NSPanel hosting contexts.
5. **Esc/dismiss persistence** — restructuring the description section must not break the existing `onDisappear → persistTitleAndNotes` path (Esc and Done both save).

---

### Task 1: Fix checklist rows not clickable in detail sheet

**Files:**
- Modify: `Sources/DayBar/TodoDetailSheet.swift:154-207` (`ChecklistRow`)
- Test: manual/smoke only (UI hit-testing is not unit-testable in XCTest)

**Interfaces:**
- Consumes: `appState.toggleChecklistItem/renameChecklistItem/deleteChecklistItem` (unchanged).
- Produces: `ChecklistRow` with clickable toggle + delete buttons in all three hosting surfaces.

Root cause is NOT yet established (systematic-debugging Phase 1 first). Hypotheses, to be classified by evidence:
- **H1 — hit-testing:** `.buttonStyle(.plain)` inside `Form` + `.formStyle(.grouped)` rows: the form row swallows mouse-down; action never fires. Standard fix: `.borderless` + explicit `.contentShape`/hit target.
- **H2 — state:** action fires but `@State items` reload doesn't re-render (unlikely: `TodoChecklistItem` is `@Model`/Observable, but verify).
- **H3 — surface:** only broken in the tray NSPanel sheet (TodayView), not the main-window sheet.

- [ ] **Step 1: Reproduce and classify**

Build and launch from terminal so `print` output is visible:

```bash
xcodegen generate
xcodebuild -project DayBar.xcodeproj -scheme DayBar -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/DayBar.app
```

Add temporary instrumentation at the top of `onToggle` and `onDelete` closures in `TodoDetailSheet.swift` (lines 76-87):

```swift
onToggle: {
    print("DEBUG toggle fired for \(item.title)")
    appState.toggleChecklistItem(item)
    reloadItems()
},
```

Manually click a checklist circle in **both** surfaces (main window Task Board detail; tray panel detail). Classification:
- No `DEBUG` line → H1 or H3 (event not delivered). Then click the toggle via Accessibility `AXPress` (AppleScript System Events) — if AXPress fires the action but mouse click doesn't, it is H1 (style/hit-testing); if the tray surface is the only broken one, H3.
- `DEBUG` line prints but checkmark doesn't change → H2.

- [ ] **Step 2: Apply the fix matching the evidence**

H1 fix (expected outcome) — in `ChecklistRow`, replace both button declarations:

```swift
Button(action: onToggle) {
    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 14))
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
        .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
}
.buttonStyle(.borderless)
.accessibilityLabel(item.isCompleted ? "Completed" : "Incomplete")
```

```swift
Button(role: .destructive, action: onDelete) {
    Image(systemName: "trash")
        .font(.caption)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
        .foregroundStyle(.secondary)
}
.buttonStyle(.borderless)
.accessibilityLabel("Delete checklist item")
```

H2 fix — replace manual `@State items` reload with direct `@Model` observation (drop the `reloadItems()` calls from the closures; keep `items` only as the insert-order source).
H3 fix — stop presenting `TodoDetailSheet` as a sheet on the tray NSPanel; present it as a borderless child window from `TodayView` instead. Do not jump here without tray-only evidence.

- [ ] **Step 3: Verify in all three surfaces**

Checklist smoke matrix (each: click toggle → checkmark flips and survives app relaunch; double-click title → inline rename commits; trash → row disappears):

| Surface | Entry |
|---|---|
| Main window | Task Board → row → detail sheet |
| Tray panel | Tray → task → detail sheet |
| History | Task History → detail sheet |

- [ ] **Step 4: Remove instrumentation, commit**

Delete the `print("DEBUG …")` lines. Run `xcodebuild … build` once to confirm clean compile.

```bash
git add Sources/DayBar/TodoDetailSheet.swift
git commit -m "fix: checklist rows in detail sheet not clickable"
bd close daybar-t07
```

---

### Task 2: Custom planned date when creating tasks on the board

**Files:**
- Modify: `Sources/DayBar/TaskBoardView.swift` (`addField` ~161-197, `addCurrent` 199-214, `BoardColumnView` ~391-509, `BoardRowView`, `BoardCardView`)
- Modify: `Sources/DayBar/TodoDetailSheet.swift` (add Planned For section)
- Modify: `Sources/DayBarCore/State/AppState.swift` (add `setPlannedDate`)
- Create: `Sources/DayBarCore/Util/DayLabel.swift`
- Test: `Tests/DayBarTests/DayLabelTests.swift` (create), `Tests/DayBarTests/PlannedDateTests.swift` (create)

**Interfaces:**
- Consumes: `AppState.addTodo(title:priority:plannedFor:now:)` — exists, `plannedFor` normalized to start-of-day; `DayMath.startOfDay/nextDay` — public.
- Produces: `AppState.setPlannedDate(_ todo: DailyTodo, to day: Date, now: Date)` — sets `plannedForDate` to `DayMath.startOfDay`, clears `snoozedUntil`, demotes `.snoozed` → `.planned`, never touches `completedDate`; pushes to Reminders + saves + refreshes. `DayLabel.relative(_ day: Date, now: Date, calendar: Calendar) -> String?` — `nil` when `day` is today, else "Tomorrow" / "Yesterday" / "14 Mar".

- [ ] **Step 1: Write failing tests for `setPlannedDate`**

`Tests/DayBarTests/PlannedDateTests.swift`:

```swift
import XCTest
@testable import DayBarCore

@MainActor
final class PlannedDateTests: XCTestCase {
    private var cal: Calendar!
    private var store: DataStore!
    private var state: AppState!

    override func setUp() {
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        store = DataStore(inMemory: true)
        state = AppState(
            store: store, calendar: cal,
            schedulesRemindersSync: false, observeSystemEvents: false,
            notesRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("PlannedDateTests-\(UUID().uuidString)")
        )
    }

    private var now: Date { Date(timeIntervalSince1970: 2_000_000_000) }

    func testSetPlannedDateNormalizesToStartOfDay() {
        let todo = state.addTodo(title: "T", plannedFor: now, now: now)!
        let later = cal.date(byAdding: .hour, value: 9, to: now)!

        state.setPlannedDate(todo, to: later, now: now)

        XCTAssertEqual(todo.plannedForDate, cal.startOfDay(for: later))
    }

    func testSetPlannedDatePreservesCompletedTask() {
        let todo = state.addTodo(title: "Done", plannedFor: now, now: now)
        state.setBoardStatus(.done, for: todo, now: now)
        let completedDate = todo.completedDate

        state.setPlannedDate(todo, to: cal.date(byAdding: .day, value: 3, to: now)!, now: now)

        XCTAssertEqual(todo.completedDate, completedDate)
        XCTAssertEqual(todo.status, .completed)
    }

    func testSetPlannedDateClearsSnooze() {
        let todo = state.addTodo(title: "S", plannedFor: now, now: now)
        todo.status = .snoozed
        todo.snoozedUntil = cal.date(byAdding: .day, value: 1, to: now)!

        state.setPlannedDate(todo, to: cal.date(byAdding: .day, value: 2, to: now)!, now: now)

        XCTAssertEqual(todo.status, .planned)
        XCTAssertNil(todo.snoozedUntil)
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `xcodebuild -project DayBar.xcodeproj -scheme DayBar test -only-testing:DayBarTests/PlannedDateTests 2>&1 | tail -20`
Expected: FAIL — `setPlannedDate` does not exist.

- [ ] **Step 3: Implement `setPlannedDate`**

In `AppState.swift`, next to `delay`/`reschedule` (~line 503):

```swift
/// Move a task's planned day without resurrecting it: completed tasks keep
/// their completion; snoozed tasks return to planned. Unlike `reschedule`,
/// this never touches `completedDate`.
public func setPlannedDate(_ todo: DailyTodo, to day: Date, now: Date = .now) {
    let planned = DayMath.startOfDay(day, calendar: calendar)
    guard planned != todo.plannedForDate else { return }
    todo.plannedForDate = planned
    todo.snoozedUntil = nil
    if todo.status == .snoozed { todo.status = .planned }
    markRemindersTodoLocallyModified(todo, now: now)
    remindersSync.enqueuePush(for: todo)
    commitSave()
    refresh(now: now)
}
```

- [ ] **Step 4: Tests pass**

Run the same command as Step 2. Expected: 3/3 PASS.

- [ ] **Step 5: `DayLabel` with failing tests first**

`Tests/DayBarTests/DayLabelTests.swift`:

```swift
import XCTest
@testable import DayBarCore

final class DayLabelTests: XCTestCase {
    private let cal = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testTodayIsNil() {
        XCTAssertNil(DayLabel.relative(now, now: now, calendar: cal))
    }

    func testTomorrow() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(DayLabel.relative(tomorrow, now: now, calendar: cal), "Tomorrow")
    }

    func testYesterday() {
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(DayLabel.relative(yesterday, now: now, calendar: cal), "Yesterday")
    }

    func testOtherDayIsDayMonth() {
        let other = cal.date(byAdding: .day, value: 5, to: now)!
        let label = DayLabel.relative(other, now: now, calendar: cal)
        XCTAssertFalse(label!.contains("Tomorrow"))
        XCTAssertFalse(label!.isEmpty)
    }
}
```

Run → FAIL (no `DayLabel`). Implement `Sources/DayBarCore/Util/DayLabel.swift`:

```swift
import Foundation

/// Short human label for a task's planned day, relative to `now`.
public enum DayLabel {
    /// `nil` when `day` is today (no chip needed).
    public static func relative(
        _ day: Date, now: Date, calendar: Calendar = .current
    ) -> String? {
        let d = DayMath.startOfDay(day, calendar: calendar)
        let t = DayMath.startOfDay(now, calendar: calendar)
        if d == t { return nil }
        if d == DayMath.nextDay(now, calendar: calendar) { return "Tomorrow" }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: t) ?? t
        if d == yesterday { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.setLocalizedDateFormatFromTemplate("d MMM")
        return fmt.string(from: d)
    }
}
```

Run → PASS.

- [ ] **Step 6: Date affordance in the bottom composer (`addField`)**

In `TaskBoardView`, add state next to `newTitle`:

```swift
@State private var composerDate: Date?
@State private var showDatePopover = false

private var scopeDefaultPlannedDate: Date {
    switch scope {
    case .tomorrow: DayMath.nextDay(.now, calendar: appState.calendar)
    default: DayMath.startOfDay(.now, calendar: appState.calendar)
    }
}
```

Extend `addField`'s `HStack` between the TextField and the return button:

```swift
if let planned = composerDate {
    Button {
        composerDate = nil
    } label: {
        Label(DayLabel.relative(planned, now: .now, calendar: appState.calendar) ?? "Today",
              systemImage: "xmark.circle.fill")
            .font(.caption)
            .labelStyle(.titleAndIcon)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .help("Clear custom date")
}
Button {
    showDatePopover = true
} label: {
    Image(systemName: "calendar.badge.plus")
}
.buttonStyle(.plain)
.foregroundStyle(addFocused || composerDate != nil ? Color.accentColor : .secondary)
.help("Pick a date")
.popover(isPresented: $showDatePopover, arrowEdge: .top) {
    VStack(alignment: .leading, spacing: 10) {
        DatePicker(
            "Planned for",
            selection: Binding(
                get: { composerDate ?? scopeDefaultPlannedDate },
                set: { composerDate = $0 }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        HStack {
            Button("Today") { composerDate = scopeDefaultPlannedDate }
            Button("Tomorrow") {
                composerDate = DayMath.nextDay(.now, calendar: appState.calendar)
            }
            Spacer()
            Button("Clear") { composerDate = nil }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    .padding(12)
    .frame(width: 320)
}
```

Note: "Today" for the `.tomorrow` scope means the scope's default (tomorrow) — for that scope relabel the first preset `Text(scope == .tomorrow ? "Tomorrow" : "Today")` via a computed preset name. Esc in the popover closes it (SwiftUI default).

Update `addCurrent()`:

```swift
private func addCurrent() {
    let title = newTitle.trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty else { return }
    let todo = appState.addTodo(
        title: title,
        plannedFor: composerDate ?? scopeDefaultPlannedDate,
        now: .now
    )
    if case .project(let id) = scope, let todo {
        appState.assign(todo: todo, to: appState.projects.first(where: { $0.id == id }))
    }
    newTitle = ""
    composerDate = nil
    addFocused = true
}
```

(The `scope == .tomorrow ? addTodoForTomorrow : addTodo` branch disappears here — `addTodoForTomorrow` remains for the tray.)

- [ ] **Step 7: Same affordance in kanban column inline add (`BoardColumnView.commitAdd`)**

Add the same `composerDate`/`showDatePopover` state and calendar button + popover to the column header row (next to the existing `+` button); the popover body is identical to Step 6 — factor it into a small shared `private struct ComposerDatePopover: View` inside `TaskBoardView.swift` taking `@Binding var date: Date?` and the default date, so both call sites use one implementation. Update `commitAdd`:

```swift
private func commitAdd() {
    let title = newTitle.trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty else {
        addingTask = false
        return
    }
    let defaultDate: Date = scope == .tomorrow
        ? DayMath.nextDay(.now, calendar: appState.calendar)
        : DayMath.startOfDay(.now, calendar: appState.calendar)
    let todo = appState.addTodo(
        title: title,
        plannedFor: composerDate ?? defaultDate,
        now: .now
    )
    if let todo {
        if case .project(let id) = scope {
            appState.assign(todo: todo, to: appState.projects.first(where: { $0.id == id }))
        }
        if column != .toDo {
            appState.setBoardStatus(column, for: todo)
        }
    }
    newTitle = ""
    composerDate = nil
    addFocused = true
}
```

- [ ] **Step 8: Date chips on rows and cards**

In `BoardRowView` (after the project chip) and `BoardCardView` (after the title), add:

```swift
if !todo.isCompleted,
   let label = DayLabel.relative(
       todo.plannedForDate, now: .now, calendar: appState.calendar
   ) {
    Text(label)
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .foregroundStyle(.secondary)
        .help("Planned for \(label)")
}
```

- [ ] **Step 9: Planned-date picker in the detail sheet**

In `TodoDetailSheet`, add `@State private var plannedDate = Date.now`, set it in `load()` (`plannedDate = todo.plannedForDate`), and add a section between Project and Description:

```swift
Section("Planned For") {
    DatePicker("Date", selection: $plannedDate, displayedComponents: .date)
        .datePickerStyle(.compact)
}
```

Wire it next to the existing `selectedProjectID` change handler:

```swift
.onChange(of: plannedDate) { _, newDate in
    appState.setPlannedDate(todo, to: newDate)
}
```

(The Form scrolls; the fixed 400×520 frame stays.)

- [ ] **Step 10: Smoke verify + edge cases**

- Board (Today scope) → calendar button → pick +5 days → type title → Enter: task appears with a "19 Oct"-style chip; it is NOT in Today's list; it IS in All Tasks.
- Same from a kanban column `+`.
- Tomorrow scope: default create lands tomorrow (no chip change needed → "Tomorrow" chip shows).
- Detail sheet: change date of a completed task → stays Done (Review Focus 1).
- Tray panel: add via composer still works (regression).

- [ ] **Step 11: Commit**

```bash
git add Sources/DayBar/TaskBoardView.swift Sources/DayBar/TodoDetailSheet.swift \
        Sources/DayBarCore/State/AppState.swift Sources/DayBarCore/Util/DayLabel.swift \
        Tests/DayBarTests/PlannedDateTests.swift Tests/DayBarTests/DayLabelTests.swift
git commit -m "feat: custom planned date on task creation and in detail sheet"
bd close daybar-xeb
```

---

### Task 3: Trello-style markdown description (edit/preview)

**Files:**
- Modify: `project.yml` (add MarkdownUI package)
- Create: `Sources/DayBarCore/Util/DescriptionMarkdown.swift`
- Modify: `Sources/DayBar/TodoDetailSheet.swift` (Description section → Write/Preview toggle)
- Test: `Tests/DayBarTests/DescriptionMarkdownTests.swift` (create)

**Interfaces:**
- Consumes: `MarkdownUI` (`Markdown(...)` view, `String: MarkdownContent`); `NotesLinkDetector.urls(in:)` — exists, `public static func urls(in string: String) -> [URL]`.
- Produces: `DescriptionMarkdown.autolinked(_ text: String) -> String` — wraps bare URLs in `<...>` unless already part of markdown (`](…)` / `<…>`); `notes` keeps storing raw markdown.

- [ ] **Step 1: Add the dependency**

In `project.yml` under `packages:` add:

```yaml
  MarkdownUI:
    url: https://github.com/gonzalezreal/swift-markdown-ui
    from: "2.4.1"
```

and under the `DayBar` target's `dependencies:` add `- package: MarkdownUI`. Then run `xcodegen generate`.

- [ ] **Step 2: Failing tests for the autolink preprocessor**

`Tests/DayBarTests/DescriptionMarkdownTests.swift`:

```swift
import XCTest
@testable import DayBarCore

final class DescriptionMarkdownTests: XCTestCase {
    func testWrapsBareURL() {
        XCTAssertEqual(
            DescriptionMarkdown.autolinked("see https://example.com/x here"),
            "see <https://example.com/x> here"
        )
    }

    func testLeavesMarkdownLinksAlone() {
        let input = "[label](https://example.com) stays"
        XCTAssertEqual(DescriptionMarkdown.autolinked(input), input)
    }

    func testLeavesAutolinksAlone() {
        let input = "already <https://example.com> done"
        XCTAssertEqual(DescriptionMarkdown.autolinked(input), input)
    }

    func testPlainTextUntouched() {
        XCTAssertEqual(DescriptionMarkdown.autolinked("no links # heading * bold"), "no links # heading * bold")
    }

    func testMultipleURLs() {
        XCTAssertEqual(
            DescriptionMarkdown.autolinked("a https://a.io b https://b.io"),
            "a <https://a.io> b <https://b.io>"
        )
    }
}
```

Run: `xcodebuild -project DayBar.xcodeproj -scheme DayBar test -only-testing:DayBarTests/DescriptionMarkdownTests 2>&1 | tail -5`
Expected: FAIL — `DescriptionMarkdown` does not exist.

- [ ] **Step 3: Implement `DescriptionMarkdown`**

`Sources/DayBarCore/Util/DescriptionMarkdown.swift`:

```swift
import Foundation

/// Prepares task-note text for markdown rendering.
public enum DescriptionMarkdown {
    /// Wraps bare URLs in `<...>` so cmark autolinks them. URLs already inside
    /// a markdown link `](...)` or an existing `<...>` autolink are untouched.
    /// Replacement runs back-to-front so earlier ranges stay valid.
    public static func autolinked(_ text: String) -> String {
        let urls = NotesLinkDetector.urls(in: text)
        guard !urls.isEmpty else { return text }

        var spans: [Range<String.Index>] = []
        for url in urls {
            guard let range = text.range(of: url.absoluteString) else { continue }
            let precededByLinkTarget = range.lowerBound > text.startIndex
                && text[text.index(before: range.lowerBound)] == "("
            let precededByAutolinkOpen = range.lowerBound > text.startIndex
                && text[text.index(before: range.lowerBound)] == "<"
            if precededByLinkTarget || precededByAutolinkOpen { continue }
            spans.append(range)
        }
        guard !spans.isEmpty else { return text }

        var result = text
        for range in spans.reversed() {
            result.replaceSubrange(range, with: "<\(text[range])>")
        }
        return result
    }
}
```

Run the tests again. Expected: 5/5 PASS.

- [ ] **Step 4: Write/Preview toggle in the detail sheet**

In `TodoDetailSheet` add `@State private var showsPreview = false`. Restructure the Description section: the section header becomes an `HStack` with `Text("Description")` + `Spacer()` + a segmented Write/Preview `Picker`; the content switches:

```swift
Section {
    if showsPreview {
        ScrollView {
            Markdown(DescriptionMarkdown.autolinked(notes))
                .markdownTextStyle {
                    ForegroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 120, maxHeight: 180)
    } else {
        TextEditor(text: $notes)
            .font(.body)
            .focused($descriptionFocused)
            .frame(minHeight: 120, maxHeight: 180)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Description")
    }
    // existing detectedLinks VStack stays below, both modes
} header: {
    HStack {
        Text("Description")
        Spacer()
        Picker("Mode", selection: $showsPreview) {
            Text("Write").tag(false)
            Text("Preview").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
    }
} footer: {
    Text("Markdown supported in Preview. Valid URLs become clickable links below.")
        .font(.caption2)
}
```

`import MarkdownUI` at the top of the file. Persistence path is untouched: `notes` still holds raw markdown (`persistTitleAndNotes` on Done/Esc). Default mode stays Write (editing-first; preview is one click away).

- [ ] **Step 5: Smoke verify**

- Legacy task with plain text containing `#`, `*`, `[x]` → Preview renders without crash; text readable (Review Focus 3).
- New task → description with heading, `- [ ]` task list item, `**bold**`, `` `code` ``, bare URL → Preview renders all; link list below still shows detected URLs; clicking one opens the browser.
- Edit → Preview → Done → reopen: markdown source intact in Write mode.
- Esc dismiss still persists description (Review Focus 5).
- Apple Reminders push: notes arrive as raw markdown text (accepted limitation — Reminders has no rich text).

- [ ] **Step 6: Full suite + commit**

Run: `xcodebuild -project DayBar.xcodeproj -scheme DayBar test 2>&1 | tail -5`
Expected: all suites PASS (existing Persistence/BoardStatus/etc. untouched).

```bash
git add project.yml Sources/DayBar/TodoDetailSheet.swift \
        Sources/DayBarCore/Util/DescriptionMarkdown.swift \
        Tests/DayBarTests/DescriptionMarkdownTests.swift
git commit -m "feat: markdown description with write/preview toggle in task detail"
bd close daybar-b8s
```

---

## Execution

Native (this session), task order 1 → 2 → 3: Task 1 unblocks real checklist usage and validates the detail sheet in all three surfaces that Tasks 2-3 then modify.
