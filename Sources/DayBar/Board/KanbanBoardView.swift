import SwiftUI
import DayBarCore

/// Three equal-width columns that fill the window (scrolling sideways only when the window
/// is narrower than three minimum-width columns). Each column scrolls vertically on its own.
struct KanbanBoardView: View {
    let scope: TaskScope
    let snapshot: BoardSnapshot
    let showProjectChip: Bool
    let selection: UUID?
    let onSelect: (DailyTodo) -> Void
    let onDelete: (DailyTodo) -> Void
    let onDrop: (DailyTodo) -> Void

    static let minColumnWidth: CGFloat = 220
    private let spacing: CGFloat = 12
    private let padding: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width - padding * 2 - spacing * 2
            let columnWidth = max(Self.minColumnWidth, (available / 3).rounded(.down))
            let fits = columnWidth * 3 + spacing * 2 + padding * 2 <= geo.size.width + 0.5
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(BoardColumn.allCases, id: \.self) { column in
                        BoardColumnView(
                            scope: scope,
                            column: column,
                            todos: snapshot.todos(in: column),
                            showProjectChip: showProjectChip,
                            lookup: { snapshot.byID[$0] },
                            selection: selection,
                            onSelect: onSelect,
                            onDelete: onDelete,
                            onDrop: onDrop
                        )
                        .frame(width: columnWidth)
                    }
                }
                .padding(padding)
                .frame(height: geo.size.height)
            }
            .scrollDisabled(fits)
            .scrollIndicators(fits ? .hidden : .automatic)
        }
    }
}
