import Foundation

/// Where a dragged row would land, from the pointer's y and the rows' vertical extents
/// (all in the drop zone's coordinate space, rows in display order). A row whose frame is
/// unknown (`nil`, e.g. not laid out yet) keeps its slot, so indices always refer to the
/// full row list.
public enum DropInsertionMath {
    public typealias RowFrame = (minY: Double, maxY: Double)

    /// First measured row whose midpoint lies below `y`; otherwise just past the last
    /// measured row (or the end when nothing is measured).
    public static func insertionIndex(locationY y: Double, rowFrames: [RowFrame?]) -> Int {
        var lastMeasured: Int?
        for (index, frame) in rowFrames.enumerated() {
            guard let frame else { continue }
            if y < (frame.minY + frame.maxY) / 2 { return index }
            lastMeasured = index
        }
        return lastMeasured.map { $0 + 1 } ?? rowFrames.count
    }

    /// Keeps the index inside the reorderable segment (e.g. above completed rows).
    public static func clamp(_ index: Int, toSegmentCount count: Int) -> Int {
        max(0, min(index, count))
    }

    /// The y at which to draw the insertion line for `index`: the gap between the rows
    /// around it (top of the next row / bottom of the previous one at the ends).
    public static func indicatorY(for index: Int, rowFrames: [RowFrame?]) -> Double? {
        let previous = index > 0 && index - 1 < rowFrames.count ? rowFrames[index - 1] : nil
        let next = index >= 0 && index < rowFrames.count ? rowFrames[index] : nil
        switch (previous, next) {
        case (let previous?, let next?): return (previous.maxY + next.minY) / 2
        case (nil, let next?): return next.minY
        case (let previous?, nil): return previous.maxY
        case (nil, nil): return nil
        }
    }
}
