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

    @Namespace private var cardNamespace

    private let spacing: CGFloat = 12
    private let padding: CGFloat = 12

    // Kept in small pieces: as one closure, Xcode 16's type checker gave up on this body.
    var body: some View {
        GeometryReader { geo in
            let layout = columnLayout(for: geo.size.width)
            ScrollView(.horizontal) {
                columns(width: layout.columnWidth)
                    .padding(padding)
                    .frame(height: geo.size.height)
            }
            .scrollDisabled(layout.fits)
            .scrollIndicators(layout.fits ? .hidden : .automatic)
        }
    }

    /// Column width for the given board width, and whether three columns fit without scrolling.
    private func columnLayout(for width: CGFloat) -> (columnWidth: CGFloat, fits: Bool) {
        let available: CGFloat = width - padding * 2 - spacing * 2
        let columnWidth: CGFloat = max(ThemeMetrics.minColumnWidth, (available / 3).rounded(.down))
        let needed: CGFloat = columnWidth * 3 + spacing * 2 + padding * 2
        return (columnWidth, needed <= width + 0.5)
    }

    private func columns(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(BoardColumn.allCases, id: \.self) { column in
                columnView(column, width: width)
            }
        }
    }

    private func columnView(_ column: BoardColumn, width: CGFloat) -> some View {
        BoardColumnView(
            scope: scope,
            column: column,
            todos: snapshot.todos(in: column),
            showProjectChip: showProjectChip,
            lookup: { snapshot.byID[$0] },
            selection: selection,
            onSelect: onSelect,
            onDelete: onDelete,
            onDrop: onDrop,
            namespace: cardNamespace
        )
        .frame(width: width)
    }
}
