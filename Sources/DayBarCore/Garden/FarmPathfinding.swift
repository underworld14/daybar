import Foundation

/// Deterministic 4-connected A* over the farm walkability grid. The grid is tiny (24×16), so a plain
/// open-list scan is more than fast enough; determinism (stable neighbour order + tie-break) keeps it
/// unit-testable.
public enum FarmPathfinding {
    /// The shortest walkable path from `from` to `to` inclusive, or `nil` if `to` is unreachable/solid.
    public static func path(
        from: GardenCell,
        to: GardenCell,
        isWalkable: (GardenCell) -> Bool
    ) -> [GardenCell]? {
        guard isWalkable(to) else { return nil }
        if from == to { return [from] }

        func h(_ c: GardenCell) -> Int { abs(c.col - to.col) + abs(c.row - to.row) }

        var gScore: [GardenCell: Int] = [from: 0]
        var cameFrom: [GardenCell: GardenCell] = [:]
        var open: Set<GardenCell> = [from]

        while !open.isEmpty {
            // Pick the open node with the lowest f = g + h; stable tie-break by (col, row).
            let current = open.min { a, b in
                let fa = (gScore[a] ?? .max) + h(a)
                let fb = (gScore[b] ?? .max) + h(b)
                if fa != fb { return fa < fb }
                if a.col != b.col { return a.col < b.col }
                return a.row < b.row
            }!

            if current == to { return reconstruct(cameFrom, current) }
            open.remove(current)

            let g = gScore[current] ?? .max
            for next in FarmWorldModel.orthogonalNeighbors(of: current) where isWalkable(next) {
                let tentative = g + 1
                if tentative < (gScore[next] ?? .max) {
                    cameFrom[next] = current
                    gScore[next] = tentative
                    open.insert(next)
                }
            }
        }
        return nil
    }

    private static func reconstruct(_ cameFrom: [GardenCell: GardenCell], _ end: GardenCell) -> [GardenCell] {
        var path = [end]
        var node = end
        while let prev = cameFrom[node] {
            path.append(prev)
            node = prev
        }
        return path.reversed()
    }
}
