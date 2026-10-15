import Foundation

/// Arrow-key movement of the board selection. The board is a list of columns (list mode is
/// one column); up/down move within a column, left/right jump to the nearest row of the
/// adjacent non-empty column.
public enum BoardNavigation {
    public enum Direction: Sendable {
        case up, down, left, right
    }

    public static func next(from current: UUID?, in columns: [[UUID]], direction: Direction) -> UUID? {
        let nonEmpty = columns.indices.filter { !columns[$0].isEmpty }
        guard let first = nonEmpty.first, let last = nonEmpty.last else { return nil }

        guard let current, let position = locate(current, in: columns) else {
            switch direction {
            case .down, .right: return columns[first].first
            case .up, .left: return columns[last].last
            }
        }

        let column = columns[position.column]
        switch direction {
        case .up:
            return column[max(position.row - 1, 0)]
        case .down:
            return column[min(position.row + 1, column.count - 1)]
        case .left, .right:
            let candidates = direction == .left
                ? nonEmpty.filter { $0 < position.column }.reversed()
                : nonEmpty.filter { $0 > position.column }
            guard let target = candidates.first else { return current }
            let targetColumn = columns[target]
            return targetColumn[min(position.row, targetColumn.count - 1)]
        }
    }

    private static func locate(_ id: UUID, in columns: [[UUID]]) -> (column: Int, row: Int)? {
        for (columnIndex, column) in columns.enumerated() {
            if let row = column.firstIndex(of: id) { return (columnIndex, row) }
        }
        return nil
    }
}
