import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that opens the DayBar panel focused on the quick-add field.
    /// Default ⌥⌘D; the user can rebind it in Settings. Carbon-backed (no Accessibility
    /// permission required).
    static let quickAdd = Self("quickAddTask", default: .init(.d, modifiers: [.command, .option]))
}
