#if DEBUG
import Foundation
import DayBarCore

/// Debug-only: `--seed-demo` fills an EMPTY store with a realistic spread of tasks so the
/// tray and board can be exercised and screenshotted. Pair with `DAYBAR_DATA_DIR` so the
/// live store is never touched.
@MainActor
enum DebugDemoSeeder {
    static func seedIfRequested(_ appState: AppState) {
        guard CommandLine.arguments.contains("--seed-demo") else { return }
        guard ((try? appState.store.allTodos()) ?? []).isEmpty else { return }
        let calendar = appState.calendar
        let now = Date.now
        let today = DayMath.startOfDay(now, calendar: calendar)
        let tomorrow = DayMath.nextDay(now, calendar: calendar)
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today) ?? today }

        let work = appState.createProject(name: "Client work", symbolName: "briefcase")
        let home = appState.createProject(name: "Home", symbolName: "house")

        func add(_ title: String, _ day: Date, _ priority: Priority, _ project: Project? = nil) -> DailyTodo? {
            let todo = appState.addTodo(title: title, priority: priority, plannedFor: day, now: now)
            if let todo, let project { appState.assign(todo: todo, to: project) }
            return todo
        }

        if let invoice = add("Send the March invoice to Rumah Kopi", today, .high, work) {
            appState.updateNotes(invoice, to: "Attach the **timesheet** and the receipt.\nhttps://example.com/invoice")
        }
        if let review = add("Review PR #42: tray reorder", today, .medium, work) {
            appState.setBoardStatus(.inProgress, for: review)
            _ = appState.addChecklistItem(to: review, title: "Read the diff")
            _ = appState.addChecklistItem(to: review, title: "Run it locally")
        }
        _ = add("Draft slides for Thursday sync", today, .low, work)
        _ = add("Buy coffee beans", today, .none, home)
        if let done = add("Water the monstera", today, .none, home) {
            appState.toggleComplete(done)
        }
        _ = add("Plan the weekend trip to Bandung", tomorrow, .medium, home)
        _ = add("Reply to the design feedback thread", tomorrow, .none, work)
        _ = add("Organize the research notes", daysAgo(5), .medium, work)
        _ = add("Book a quiet focus block", daysAgo(3), .none)
        _ = add("Call the landlord about the AC", daysAgo(1), .high, home)

        _ = appState.addHabitTemplate(title: "Morning stretch", cueText: "After the first glass of water")
        _ = appState.addHabitTemplate(title: "Read for 20 minutes", cueText: "Before opening messages")
        // A week of focus history so the Dayscape strip and streak have something to show.
        for daysBack in 1...6 where daysBack != 4 {
            for session in 0..<(daysBack % 3 + 1) {
                let ended = calendar.date(byAdding: .hour, value: 10 + session * 2, to: daysAgo(daysBack)) ?? today
                appState.store.insert(FocusSession(endedAt: ended, minutes: 25, completed: true))
            }
        }
        appState.store.save()
        appState.refresh()
        if let stretch = appState.todayHabits.first(where: { $0.template.title == "Morning stretch" }) {
            appState.toggleHabit(stretch.log)
        }
    }
}
#endif
