import Foundation

/// Terrain kind of a farm cell. Grass/path/bridge are walkable; water/soil are not (props/fences are
/// tracked separately in `solidStaticCells`).
public enum FarmTerrain: String, Sendable, Equatable {
    case grass, path, water, soil, bridge
}

/// What a clicked cell resolves to for interaction.
public enum FarmInteractionTarget: Equatable, Sendable {
    case plot(Int)       // engine slot index
    case animal(UUID)    // owned-animal id
    case sign
    case none
}

/// Sprite-name mapping for the big roaming farm — the superset of the site's `GardenTileCatalog`.
/// Shared tiles (grass/path/soil/crop/companion/fence/home/sign/fx) reuse `GardenTileCatalog`;
/// `allExpectedNames` here lists ONLY the farm-new sprites. The drift test asserts the manifest equals
/// `GardenTileCatalog.allExpectedNames ∪ FarmTileCatalog.allExpectedNames`.
public enum FarmTileCatalog {
    // Water autotile (orthogonal; the river is a convex rectangle so no inner corners are needed).
    public static func water(_ kind: String) -> String { "water_\(kind)" }
    public static let waterKinds = ["center", "edge_n", "edge_s", "edge_w", "edge_e",
                                    "corner_nw", "corner_ne", "corner_sw", "corner_se"]

    public static let bridgeH = "prop_bridge_h"
    public static let bridgeV = "prop_bridge_v"
    public static let barn = "prop_barn"

    // Farmer character.
    public static let charDirs = ["down", "up", "left", "right"]
    public static let walkFrames = 1...4
    public static func character(idle dir: String) -> String { "char_idle_\(dir)" }
    public static func character(walk dir: String, frame: Int) -> String { "char_walk_\(dir)_\(frame)" }

    public static func animal(_ kind: AnimalKind, ready: Bool) -> String {
        "\(kind.spriteBase)_\(ready ? "ready" : "idle")"
    }

    /// Farm-new sprite names (does NOT re-list `GardenTileCatalog`'s shared names).
    public static var allExpectedNames: Set<String> {
        var names = Set<String>()
        for k in waterKinds { names.insert(water(k)) }
        names.formUnion([bridgeH, bridgeV, barn])
        for d in charDirs {
            names.insert(character(idle: d))
            for f in walkFrames { names.insert(character(walk: d, frame: f)) }
        }
        for kind in AnimalKind.allCases {
            names.insert(animal(kind, ready: false))
            names.insert(animal(kind, ready: true))
        }
        return names
    }
}

/// A larger, explorable top-down farm: grass, a bisecting river crossed by a bridge, four crop beds,
/// a cottage, a barn, and an animal pen. Pure + deterministic so walkability, interaction targeting,
/// and layout are all unit-testable; the SpriteKit scene is a thin renderer on top.
public enum FarmWorldModel {
    public static let cols = 24
    public static let rows = 16   // row 0 = TOP, matching GardenSceneModel + the site JS

    // MARK: - Feature cells

    static let riverCols = 14...16
    static let riverRows = 1...14
    static let pathRow = 8

    /// The bridge decking (walkable, drawn over the water).
    public static let bridgeCells: Set<GardenCell> = [GardenCell(14, 8), GardenCell(15, 8), GardenCell(16, 8)]

    /// Engine slot index → scene cell (left region). Solid soil; the farmer stands adjacent.
    public static let plotCells = [GardenCell(5, 6), GardenCell(7, 6), GardenCell(9, 6), GardenCell(11, 6)]
    public static let cottageCell = GardenCell(2, 2)   // 2×2 prop_home
    public static let barnCell = GardenCell(18, 2)     // 2×2 prop_barn (right region)
    public static let signCell = GardenCell(4, 2)
    public static let companionCell = GardenCell(4, 4)
    /// Owned-animal `cell` index → scene cell (right region, across the bridge).
    public static let penCells = [GardenCell(18, 7), GardenCell(21, 7), GardenCell(18, 10), GardenCell(21, 10)]

    // MARK: - Derived sets (computed once)

    private static func footprint(_ origin: GardenCell, _ w: Int, _ h: Int) -> Set<GardenCell> {
        var s = Set<GardenCell>()
        for dc in 0..<w { for dr in 0..<h { s.insert(GardenCell(origin.col + dc, origin.row + dr)) } }
        return s
    }

    /// The full river band including the cells under the bridge (used for water autotiling continuity).
    static let riverBand: Set<GardenCell> = {
        var s = Set<GardenCell>()
        for c in riverCols { for r in riverRows { s.insert(GardenCell(c, r)) } }
        return s
    }()

    /// Cells that render a water sprite (band minus the bridge, which is drawn on top and is walkable).
    public static let waterCells: Set<GardenCell> = riverBand.subtracting(bridgeCells)

    public static let cottageFootprint = footprint(cottageCell, 2, 2)
    public static let barnFootprint = footprint(barnCell, 2, 2)
    static let soilCells: Set<GardenCell> = Set(plotCells)

    public static func fenceKind(col: Int, row: Int) -> String? {
        let lastC = cols - 1, lastR = rows - 1
        switch (col, row) {
        case (0, 0): return "nw"
        case (lastC, 0): return "ne"
        case (0, lastR): return "sw"
        case (lastC, lastR): return "se"
        default:
            if row == 0 { return "n" }
            if row == lastR { return "s" }
            if col == 0 { return "w" }
            if col == lastC { return "e" }
            return nil
        }
    }

    static let fenceCells: Set<GardenCell> = {
        var s = Set<GardenCell>()
        for r in 0..<rows {
            for c in 0..<cols where fenceKind(col: c, row: r) != nil { s.insert(GardenCell(c, r)) }
        }
        return s
    }()

    /// Cosmetic east–west path spine on `pathRow` (bridge cells excepted).
    static let pathCells: Set<GardenCell> = {
        var s = Set<GardenCell>()
        for c in 1..<(cols - 1) {
            let cell = GardenCell(c, pathRow)
            if !bridgeCells.contains(cell) && !waterCells.contains(cell) { s.insert(cell) }
        }
        return s
    }()

    /// Everything the farmer cannot walk through (excluding animals, which are dynamic).
    static let solidStaticCells: Set<GardenCell> = fenceCells
        .union(waterCells).union(soilCells)
        .union(cottageFootprint).union(barnFootprint)
        .union([signCell])

    // MARK: - Terrain

    public static func terrain(col: Int, row: Int) -> FarmTerrain {
        let cell = GardenCell(col, row)
        if bridgeCells.contains(cell) { return .bridge }
        if waterCells.contains(cell) { return .water }
        if soilCells.contains(cell) { return .soil }
        if pathCells.contains(cell) { return .path }
        return .grass
    }

    // MARK: - Walkability & interaction

    public static func isWalkable(_ cell: GardenCell, animals: [AnimalSnapshot]) -> Bool {
        guard cell.col >= 0, cell.col < cols, cell.row >= 0, cell.row < rows else { return false }
        if solidStaticCells.contains(cell) { return false }
        if animalCell(at: cell, animals: animals) != nil { return false }
        return true
    }

    public static func interactionTarget(at cell: GardenCell, animals: [AnimalSnapshot]) -> FarmInteractionTarget {
        if let idx = plotCells.firstIndex(of: cell) { return .plot(idx) }
        if let id = animalCell(at: cell, animals: animals) { return .animal(id) }
        if cell == signCell { return .sign }
        return .none
    }

    /// The best walkable orthogonal neighbour of `target` to stand on (closest to the farmer), or `nil`.
    public static func adjacentWalkableCell(
        to target: GardenCell, from farmer: GardenCell, animals: [AnimalSnapshot]
    ) -> GardenCell? {
        let neighbors = orthogonalNeighbors(of: target)
        let walkable = neighbors.filter { isWalkable($0, animals: animals) }
        return walkable.min { lhs, rhs in
            let dl = manhattan(lhs, farmer), dr = manhattan(rhs, farmer)
            if dl != dr { return dl < dr }
            if lhs.col != rhs.col { return lhs.col < rhs.col }
            return lhs.row < rhs.row
        }
    }

    /// The owned-animal id occupying `cell`, if any.
    static func animalCell(at cell: GardenCell, animals: [AnimalSnapshot]) -> UUID? {
        for a in animals {
            if let idx = a.cell, penCells.indices.contains(idx), penCells[idx] == cell { return a.id }
        }
        return nil
    }

    static func orthogonalNeighbors(of c: GardenCell) -> [GardenCell] {
        [GardenCell(c.col, c.row - 1), GardenCell(c.col + 1, c.row),
         GardenCell(c.col, c.row + 1), GardenCell(c.col - 1, c.row)]
    }

    static func manhattan(_ a: GardenCell, _ b: GardenCell) -> Int {
        abs(a.col - b.col) + abs(a.row - b.row)
    }

    // MARK: - Water autotiling (orthogonal 4-bit)

    public static func waterTileName(col: Int, row: Int) -> String {
        func isWater(_ c: Int, _ r: Int) -> Bool { riverBand.contains(GardenCell(c, r)) }
        let n = isWater(col, row - 1), s = isWater(col, row + 1)
        let w = isWater(col - 1, row), e = isWater(col + 1, row)
        switch (n, e, s, w) {
        case (true, true, true, true): return FarmTileCatalog.water("center")
        case (false, true, true, true): return FarmTileCatalog.water("edge_n")
        case (true, true, false, true): return FarmTileCatalog.water("edge_s")
        case (true, true, true, false): return FarmTileCatalog.water("edge_w")
        case (true, false, true, true): return FarmTileCatalog.water("edge_e")
        case (false, true, true, false): return FarmTileCatalog.water("corner_nw")
        case (false, false, true, true): return FarmTileCatalog.water("corner_ne")
        case (true, true, false, false): return FarmTileCatalog.water("corner_sw")
        case (true, false, false, true): return FarmTileCatalog.water("corner_se")
        default: return FarmTileCatalog.water("center")
        }
    }

    // MARK: - Placements (back-to-front painter order)

    public static func placements(for snap: GardenSnapshot) -> [GardenTilePlacement] {
        var out: [GardenTilePlacement] = []

        // 1) grass base
        for row in 0..<rows {
            for col in 0..<cols {
                out.append(GardenTilePlacement(GardenTileCatalog.grass(col: col, row: row), col, row))
            }
        }
        // 2) path spine
        for cell in pathCells.sorted(by: cellOrder) {
            out.append(GardenTilePlacement(GardenTileCatalog.path, cell.col, cell.row))
        }
        // 3) water (autotiled)
        for cell in waterCells.sorted(by: cellOrder) {
            out.append(GardenTilePlacement(waterTileName(col: cell.col, row: cell.row), cell.col, cell.row))
        }
        // 4) bridge decking over the water
        for cell in bridgeCells.sorted(by: cellOrder) {
            out.append(GardenTilePlacement(FarmTileCatalog.bridgeH, cell.col, cell.row))
        }
        // 5) tilled soil under each active plot
        for (i, _) in snap.slots.enumerated() where i < plotCells.count {
            let c = plotCells[i]
            out.append(GardenTilePlacement(GardenTileCatalog.soil(snap.season), c.col, c.row))
        }
        // 6) props
        out.append(GardenTilePlacement(GardenTileCatalog.home, cottageCell.col, cottageCell.row, wTiles: 2, hTiles: 2))
        out.append(GardenTilePlacement(FarmTileCatalog.barn, barnCell.col, barnCell.row, wTiles: 2, hTiles: 2))
        out.append(GardenTilePlacement(GardenTileCatalog.sign, signCell.col, signCell.row))
        // 7) crops (planted slots)
        for (i, slot) in snap.slots.enumerated() where i < plotCells.count && !slot.isEmpty {
            let c = plotCells[i]
            let id = slot.cropID ?? GardenCatalog.defaultCropID
            out.append(GardenTilePlacement(GardenTileCatalog.crop(id, stage: slot.stage), c.col, c.row))
        }
        // 8) ready sparkle on mature slots
        for (i, slot) in snap.slots.enumerated() where i < plotCells.count && slot.isMature {
            let c = plotCells[i]
            out.append(GardenTilePlacement(GardenTileCatalog.sparkle, c.col, c.row))
        }
        // 9) animals (with ready state) + sparkle when a product is waiting
        for a in snap.animals {
            guard let idx = a.cell, penCells.indices.contains(idx) else { continue }
            let c = penCells[idx]
            out.append(GardenTilePlacement(FarmTileCatalog.animal(a.kind, ready: a.hasProduct), c.col, c.row))
            if a.hasProduct {
                out.append(GardenTilePlacement(GardenTileCatalog.sparkle, c.col, c.row))
            }
        }
        // 10) companion
        out.append(GardenTilePlacement(GardenTileCatalog.companion(snap.companionMood),
                                       companionCell.col, companionCell.row))
        // 11) fence perimeter
        for row in 0..<rows {
            for col in 0..<cols {
                if let kind = fenceKind(col: col, row: row) {
                    out.append(GardenTilePlacement(GardenTileCatalog.fence(kind), col, row))
                }
            }
        }
        // 12) weather overlay over interior cells
        if snap.weather == .rain {
            for row in 0..<rows {
                for col in 0..<cols where fenceKind(col: col, row: row) == nil {
                    out.append(GardenTilePlacement(GardenTileCatalog.rain, col, row))
                }
            }
        }
        return out
    }

    private static func cellOrder(_ a: GardenCell, _ b: GardenCell) -> Bool {
        a.row != b.row ? a.row < b.row : a.col < b.col
    }
}
