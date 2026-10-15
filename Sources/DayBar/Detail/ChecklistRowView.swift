import SwiftUI
import DayBarCore

/// One checklist line: toggle, inline rename, delete. Clicking the text toggles it.
struct ChecklistRowView: View {
    let item: TodoChecklistItem
    var onToggle: () -> Void
    var onRename: (String) -> Void
    var onDelete: () -> Void

    @State private var draft = ""
    @State private var isEditing = false
    @State private var isHovered = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")

            if isEditing {
                TextField("Item", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commitRename)
                    .onExitCommand {
                        isEditing = false
                        focused = false
                    }
                    .onChange(of: focused) { _, on in
                        if !on && isEditing { commitRename() }
                    }
            } else {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isEditing { onToggle() }
                    }
            }

            if !isEditing {
                Button(action: startEditing) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0.45)
                .accessibilityLabel("Rename checklist item")
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0.45)
            .accessibilityLabel("Delete checklist item")
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
        )
        .onHover { isHovered = $0 }
    }

    private func startEditing() {
        draft = item.title
        isEditing = true
        focused = true
    }

    private func commitRename() {
        onRename(draft)
        isEditing = false
        focused = false
    }
}
