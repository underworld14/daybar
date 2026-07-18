import XCTest
@testable import DayBarCore

/// Pure farm-world layout, walkability, interaction targeting, and pathfinding.
final class FarmWorldModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snap(animals: [AnimalSnapshot] = []) -> GardenSnapshot {
        GardenSnapshot(
            slots: GardenPlotSlot.emptySlots(count: 4),
            companionMood: .idle, season: .summer,
            coins: 0, currentStreak: 0, graceRemaining: 0,
            animals: animals
        )
    }

    private func animal(cell: Int, kind: AnimalKind = .chicken, ready: Bool = false) -> AnimalSnapshot {
        AnimalSnapshot(id: UUID(), kind: kind, cell: cell, hasProduct: ready, energyUntilReady: ready ? 0 : 3)
    }

    // MARK: - Dimensions & terrain

    func testDimensions() {
        XCTAssertEqual(FarmWorldModel.cols, 24)
        XCTAssertEqual(FarmWorldModel.rows, 16)
    }

    func testTerrainSpotChecks() {
        // A river cell that is not under the bridge is water.
        XCTAssertEqual(FarmWorldModel.terrain(col: 15, row: 3), .water)
        // Bridge decking is bridge (walkable).
        for c in FarmWorldModel.bridgeCells {
            XCTAssertEqual(FarmWorldModel.terrain(col: c.col, row: c.row), .bridge)
        }
        // Plot beds are soil.
        for c in FarmWorldModel.plotCells {
            XCTAssertEqual(FarmWorldModel.terrain(col: c.col, row: c.row), .soil)
        }
        // A left-region open cell is grass.
        XCTAssertEqual(FarmWorldModel.terrain(col: 2, row: 8), .path)   // on the spine
        XCTAssertEqual(FarmWorldModel.terrain(col: 2, row: 10), .grass)
    }

    func testBridgeCellsAreNotWater() {
        for c in FarmWorldModel.bridgeCells {
            XCTAssertFalse(FarmWorldModel.waterCells.contains(c))
        }
    }

    // MARK: - Walkability

    func testWalkabilityMatrix() {
        // Water is solid.
        XCTAssertFalse(FarmWorldModel.isWalkable(GardenCell(15, 3), animals: []))
        // Bridge is walkable.
        XCTAssertTrue(FarmWorldModel.isWalkable(GardenCell(15, 8), animals: []))
        // Fence perimeter is solid.
        XCTAssertFalse(FarmWorldModel.isWalkable(GardenCell(0, 0), animals: []))
        // Plot soil is solid.
        XCTAssertFalse(FarmWorldModel.isWalkable(FarmWorldModel.plotCells[0], animals: []))
        // Cottage footprint is solid.
        XCTAssertFalse(FarmWorldModel.isWalkable(GardenCell(2, 2), animals: []))
        // Grass is walkable.
        XCTAssertTrue(FarmWorldModel.isWalkable(GardenCell(2, 10), animals: []))
        // Out of bounds is not walkable.
        XCTAssertFalse(FarmWorldModel.isWalkable(GardenCell(-1, 5), animals: []))
        XCTAssertFalse(FarmWorldModel.isWalkable(GardenCell(24, 5), animals: []))
    }

    func testAnimalOccupiedCellIsSolid() {
        let a = animal(cell: 0)
        let penCell = FarmWorldModel.penCells[0]
        XCTAssertTrue(FarmWorldModel.isWalkable(penCell, animals: []))       // empty pen: walkable
        XCTAssertFalse(FarmWorldModel.isWalkable(penCell, animals: [a]))     // occupied: solid
    }

    // MARK: - Interaction targeting

    func testInteractionTargets() {
        XCTAssertEqual(FarmWorldModel.interactionTarget(at: FarmWorldModel.plotCells[2], animals: []), .plot(2))
        XCTAssertEqual(FarmWorldModel.interactionTarget(at: FarmWorldModel.signCell, animals: []), .sign)
        XCTAssertEqual(FarmWorldModel.interactionTarget(at: GardenCell(2, 10), animals: []), .none)

        let a = animal(cell: 1)
        XCTAssertEqual(FarmWorldModel.interactionTarget(at: FarmWorldModel.penCells[1], animals: [a]), .animal(a.id))
    }

    // MARK: - Adjacency invariant: every interactable has ≥1 walkable neighbour

    func testEveryInteractableHasWalkableNeighbour() {
        let farmer = GardenCell(6, 8)
        for plot in FarmWorldModel.plotCells {
            XCTAssertNotNil(FarmWorldModel.adjacentWalkableCell(to: plot, from: farmer, animals: []),
                            "plot \(plot) has no walkable neighbour")
        }
        XCTAssertNotNil(FarmWorldModel.adjacentWalkableCell(to: FarmWorldModel.signCell, from: farmer, animals: []))
        // Fill every pen cell and confirm each stays reachable.
        let animals = (0..<FarmWorldModel.penCells.count).map { animal(cell: $0) }
        for (i, pen) in FarmWorldModel.penCells.enumerated() {
            XCTAssertNotNil(FarmWorldModel.adjacentWalkableCell(to: pen, from: farmer, animals: animals),
                            "pen \(i) at \(pen) has no walkable neighbour")
        }
    }

    // MARK: - Pathfinding

    private func isWalkable(_ c: GardenCell) -> Bool { FarmWorldModel.isWalkable(c, animals: []) }

    func testPathIsContiguousAndWalkable() {
        let path = FarmPathfinding.path(from: GardenCell(2, 10), to: GardenCell(11, 10), isWalkable: isWalkable)
        let p = try! XCTUnwrap(path)
        XCTAssertEqual(p.first, GardenCell(2, 10))
        XCTAssertEqual(p.last, GardenCell(11, 10))
        for step in p { XCTAssertTrue(isWalkable(step)) }
        for i in 1..<p.count {
            XCTAssertEqual(FarmWorldModel.manhattan(p[i - 1], p[i]), 1, "non-adjacent step")
        }
    }

    func testPathAcrossRiverUsesBridgeAndNeverEntersWater() {
        // Left bank → right bank must detour over the bridge.
        let path = FarmPathfinding.path(from: GardenCell(3, 8), to: GardenCell(20, 8), isWalkable: isWalkable)
        let p = try! XCTUnwrap(path)
        XCTAssertTrue(p.contains { FarmWorldModel.bridgeCells.contains($0) }, "path did not cross the bridge")
        for step in p {
            XCTAssertFalse(FarmWorldModel.waterCells.contains(step), "path entered open water at \(step)")
        }
    }

    func testUnreachableTargetReturnsNil() {
        // A water cell is solid → no path.
        XCTAssertNil(FarmPathfinding.path(from: GardenCell(2, 10), to: GardenCell(15, 3), isWalkable: isWalkable))
        // A fence cell is solid → no path.
        XCTAssertNil(FarmPathfinding.path(from: GardenCell(2, 10), to: GardenCell(0, 0), isWalkable: isWalkable))
    }

    func testBothRiverBanksAreBridgeConnected() {
        // A representative cell on each bank routes to the other.
        XCTAssertNotNil(FarmPathfinding.path(from: GardenCell(2, 2 + 3), to: GardenCell(20, 12), isWalkable: isWalkable))
        XCTAssertNotNil(FarmPathfinding.path(from: GardenCell(20, 12), to: GardenCell(5, 5), isWalkable: isWalkable))
    }

    // MARK: - Placements

    func testPlacementsPainterOrderAndContent() {
        let readyAnimal = animal(cell: 0, kind: .cow, ready: true)
        let places = FarmWorldModel.placements(for: snap(animals: [readyAnimal]))
        // Grass base is laid first.
        XCTAssertTrue(places.first?.name.hasPrefix("tile_grass_") ?? false)
        // Water, bridge, barn, and the animal all appear.
        XCTAssertTrue(places.contains { $0.name.hasPrefix("water_") })
        XCTAssertTrue(places.contains { $0.name == FarmTileCatalog.bridgeH })
        XCTAssertTrue(places.contains { $0.name == FarmTileCatalog.barn && $0.wTiles == 2 && $0.hTiles == 2 })
        XCTAssertTrue(places.contains { $0.name == "animal_cow_ready" })
        // Water is painted before the bridge.
        let firstWater = places.firstIndex { $0.name.hasPrefix("water_") }!
        let firstBridge = places.firstIndex { $0.name == FarmTileCatalog.bridgeH }!
        XCTAssertLessThan(firstWater, firstBridge)
    }

    func testWaterAutotileProducesCenterAndEdges() {
        let places = FarmWorldModel.placements(for: snap())
        let waterNames = Set(places.filter { $0.name.hasPrefix("water_") }.map(\.name))
        // A 3-wide rectangular river exercises center + side edges + corners.
        XCTAssertTrue(waterNames.contains(FarmTileCatalog.water("center")))
        XCTAssertTrue(waterNames.contains(FarmTileCatalog.water("edge_w")))
        XCTAssertTrue(waterNames.contains(FarmTileCatalog.water("edge_e")))
    }
}
