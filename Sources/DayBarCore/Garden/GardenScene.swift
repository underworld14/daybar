import Foundation

/// A cell in the fixed 10×6 garden grid.
public struct GardenCell: Equatable, Hashable, Sendable {
    public var col: Int
    public var row: Int
    public init(_ col: Int, _ row: Int) { self.col = col; self.row = row }
}

/// One sprite drawn into the scene at a grid cell. `wTiles`/`hTiles` allow multi-tile props
/// (the cottage is 2×2). Placements are emitted back-to-front (painter's order).
public struct GardenTilePlacement: Equatable, Sendable {
    public var name: String
    public var col: Int
    public var row: Int
    public var wTiles: Int
    public var hTiles: Int
    public init(_ name: String, _ col: Int, _ row: Int, wTiles: Int = 1, hTiles: Int = 1) {
        self.name = name
        self.col = col
        self.row = row
        self.wTiles = wTiles
        self.hTiles = hTiles
    }
}

/// Maps engine state to sprite names. The name set here MUST match `manifest.json`
/// (asserted by GardenSceneTests) so the app and the exported web sheet never drift.
public enum GardenTileCatalog {
    public static func grass(col: Int, row: Int) -> String {
        (col * 3 + row * 5) % 7 == 0 ? "tile_grass_b" : "tile_grass_a"
    }
    public static let path = "tile_path"
    public static func soil(_ season: GardenSeason) -> String { "plot_soil_\(season.rawValue)" }
    public static func crop(_ id: String, stage: Int) -> String {
        "crop_\(id)_top_\(min(GardenCatalog.maxStage, max(1, stage)))"
    }
    public static func companion(_ mood: CompanionMood) -> String { "companion_\(mood.rawValue)_down" }
    public static func fence(_ kind: String) -> String { "fence_\(kind)" }
    public static let home = "prop_home"
    public static let sign = "prop_sign"
    public static let rain = "fx_rain_16"
    public static let highlight = "fx_highlight"
    public static let sparkle = "fx_sparkle"

    static let fenceKinds = ["n", "s", "w", "e", "nw", "ne", "sw", "se"]
    static let companionMoods = ["idle", "happy", "wilted"]

    /// Every sprite name the catalog can emit — compared against the manifest in tests.
    public static var allExpectedNames: Set<String> {
        var names: Set<String> = [path, home, sign, rain, highlight, sparkle,
                                  "tile_grass_a", "tile_grass_b"]
        for s in GardenSeason.allCases { names.insert(soil(s)) }
        for k in fenceKinds { names.insert(fence(k)) }
        for id in GardenCatalog.cropRotation {
            for st in 1...GardenCatalog.maxStage { names.insert(crop(id, stage: st)) }
        }
        for m in companionMoods { names.insert("companion_\(m)_down") }
        return names
    }
}

/// Builds the fixed top-down farm layout from a `GardenSnapshot`. Pure + deterministic.
public enum GardenSceneModel {
    public static let cols = 10
    public static let rows = 6
    /// Engine slot index → scene cell (up to `GardenCatalog.maxSlotCount`).
    public static let plotCells = [GardenCell(2, 3), GardenCell(4, 3), GardenCell(6, 3), GardenCell(8, 3)]
    public static let companionCell = GardenCell(5, 4)
    public static let homeCell = GardenCell(1, 1) // 2×2 cottage
    public static let signCell = GardenCell(7, 1)
    public static let pathRow = 4

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

    /// Back-to-front sprite placements for the whole scene.
    public static func placements(for snap: GardenSnapshot) -> [GardenTilePlacement] {
        var out: [GardenTilePlacement] = []

        // 1) grass base
        for row in 0..<rows {
            for col in 0..<cols {
                out.append(GardenTilePlacement(GardenTileCatalog.grass(col: col, row: row), col, row))
            }
        }
        // 2) path strip
        for col in 1..<(cols - 1) {
            out.append(GardenTilePlacement(GardenTileCatalog.path, col, pathRow))
        }
        // 3) tilled soil under each active plot
        for (i, _) in snap.slots.enumerated() where i < plotCells.count {
            let c = plotCells[i]
            out.append(GardenTilePlacement(GardenTileCatalog.soil(snap.season), c.col, c.row))
        }
        // 4) props
        out.append(GardenTilePlacement(GardenTileCatalog.home, homeCell.col, homeCell.row, wTiles: 2, hTiles: 2))
        out.append(GardenTilePlacement(GardenTileCatalog.sign, signCell.col, signCell.row))
        // 5) crops (planted slots)
        for (i, slot) in snap.slots.enumerated() where i < plotCells.count && !slot.isEmpty {
            let c = plotCells[i]
            let id = slot.cropID ?? GardenCatalog.defaultCropID
            out.append(GardenTilePlacement(GardenTileCatalog.crop(id, stage: slot.stage), c.col, c.row))
        }
        // 6) ready sparkle on mature slots
        for (i, slot) in snap.slots.enumerated() where i < plotCells.count && slot.isMature {
            let c = plotCells[i]
            out.append(GardenTilePlacement(GardenTileCatalog.sparkle, c.col, c.row))
        }
        // 7) companion
        out.append(GardenTilePlacement(GardenTileCatalog.companion(snap.companionMood),
                                       companionCell.col, companionCell.row))
        // 8) fence perimeter (front of interior edge props)
        for row in 0..<rows {
            for col in 0..<cols {
                if let kind = fenceKind(col: col, row: row) {
                    out.append(GardenTilePlacement(GardenTileCatalog.fence(kind), col, row))
                }
            }
        }
        // 9) weather overlay over interior cells
        if snap.weather == .rain {
            for row in 0..<rows {
                for col in 0..<cols where fenceKind(col: col, row: row) == nil {
                    out.append(GardenTilePlacement(GardenTileCatalog.rain, col, row))
                }
            }
        }
        return out
    }
}
