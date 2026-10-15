import Foundation

/// Layout policy for the menu-bar tray list. Extracted so the empty→visible
/// mounting rules are unit-tested — the long-lived `NSHostingView` otherwise
/// can miss a newly inserted section until the panel is reopened.
public enum TraySectionPolicy {
    /// Whether the TOMORROW block should be in the view tree.
    /// Always `true` — even at count 0 — so the first tomorrow add updates in place
    /// inside the long-lived tray `NSHostingView` (conditional mount stayed stale until reopen).
    public static func showsTomorrowSection(todoCount: Int) -> Bool {
        // Count is accepted so call sites keep reading `tomorrowTodos` (observation),
        // but emptiness must never unmount the section.
        _ = todoCount
        return true
    }

    /// Whether the "Now" card (in-progress tasks + focus timer) is in the view tree.
    /// Always `true` for the same reason as Tomorrow; an empty card renders at zero height.
    public static func showsNowSection(inProgressCount: Int) -> Bool {
        _ = inProgressCount
        return true
    }
}
