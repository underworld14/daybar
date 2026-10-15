import Foundation

/// Where a dragged row would land, from the pointer's y and the rows' vertical extents
/// (all in the drop zone's coordinate space, rows in display order).
public enum DropInsertionMath {
    /// First row whose midpoint lies below `y`; `rows.count` past the last row.
    public static func insertionIndex(locationY y: Double, rowMidYs: [Double]) -> Int {
        rowMidYs.firstIndex(where: { y < $0 }) ?? rowMidYs.count
    }

    /// Keeps the index inside the reorderable segment (e.g. above completed rows).
    public static func clamp(_ index: Int, toSegmentCount count: Int) -> Int {
        max(0, min(index, count))
    }

    /// The y at which to draw the insertion line for `index`: the gap between the rows
    /// around it (top of the first row / bottom of the last row at the ends).
    public static func indicatorY(for index: Int, rowFrames: [(minY: Double, maxY: Double)]) -> Double? {
        guard !rowFrames.isEmpty else { return nil }
        if index <= 0 { return rowFrames[0].minY }
        if index >= rowFrames.count { return rowFrames[rowFrames.count - 1].maxY }
        return (rowFrames[index - 1].maxY + rowFrames[index].minY) / 2
    }
}
