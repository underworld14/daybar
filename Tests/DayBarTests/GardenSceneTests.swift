import XCTest
@testable import DayBarCore

final class GardenSceneTests: XCTestCase {
    private func snap(
        slots: [GardenPlotSlot],
        season: GardenSeason = .autumn,
        mood: CompanionMood = .idle,
        weather: GardenWeather = .clear
    ) -> GardenSnapshot {
        GardenSnapshot(slots: slots, companionMood: mood, season: season,
                       coins: 0, currentStreak: 0, graceRemaining: 0, weather: weather)
    }

    private func placements(_ s: GardenSnapshot) -> [GardenTilePlacement] {
        GardenSceneModel.placements(for: s)
    }

    // MARK: - Catalog ↔ manifest drift guard

    func testCatalogNamesMatchManifest() throws {
        // Locate the committed manifest relative to this source file (repo/Tests/DayBarTests/…).
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifestURL = repo.appendingPathComponent("ThirdParty/garden-pixel-src/manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let manifestNames = Set((json["sprites"] as! [String: Any]).keys)
        // The site scene uses GardenTileCatalog (10×6); the app's roaming farm adds FarmTileCatalog.
        // The manifest is the union of both.
        let catalogNames = GardenTileCatalog.allExpectedNames.union(FarmTileCatalog.allExpectedNames)
        XCTAssertEqual(catalogNames, manifestNames,
                       "Catalog names and manifest sprites drifted — regenerate art or fix the catalog.")
    }

    // MARK: - Layout

    func testSoilPlacedUnderEachSlot() {
        let s = snap(slots: GardenPlotSlot.emptySlots(count: 3))
        let soils = placements(s).filter { $0.name.hasPrefix("plot_soil_") }
        XCTAssertEqual(soils.count, 3)
        let cells = Set(soils.map { GardenCell($0.col, $0.row) })
        for c in GardenSceneModel.plotCells.prefix(3) {
            XCTAssertTrue(cells.contains(c))
        }
    }

    func testCropPlacementUsesStageAndCrop() {
        var slots = GardenPlotSlot.emptySlots(count: 3)
        slots[1] = GardenPlotSlot(index: 1, cropID: "parsnip", stage: 3)
        let cell = GardenSceneModel.plotCells[1]
        let crop = placements(snap(slots: slots)).first { $0.name == "crop_parsnip_top_3" }
        XCTAssertNotNil(crop)
        XCTAssertEqual(crop?.col, cell.col)
        XCTAssertEqual(crop?.row, cell.row)
    }

    func testSparkleOnlyForMatureSlots() {
        var slots = GardenPlotSlot.emptySlots(count: 3)
        slots[0] = GardenPlotSlot(index: 0, cropID: "berry", stage: 4)   // mature
        slots[1] = GardenPlotSlot(index: 1, cropID: "berry", stage: 2)   // growing
        let sparkles = placements(snap(slots: slots)).filter { $0.name == GardenTileCatalog.sparkle }
        XCTAssertEqual(sparkles.count, 1)
        XCTAssertEqual(sparkles.first.map { GardenCell($0.col, $0.row) }, GardenSceneModel.plotCells[0])
    }

    func testCompanionMoodName() {
        let p = placements(snap(slots: GardenPlotSlot.emptySlots(count: 3), mood: .happy))
        let comp = p.first { $0.name.hasPrefix("companion_") }
        XCTAssertEqual(comp?.name, "companion_happy_down")
        XCTAssertEqual(comp.map { GardenCell($0.col, $0.row) }, GardenSceneModel.companionCell)
    }

    func testRainOverlayOnlyWhenRaining() {
        let clear = placements(snap(slots: GardenPlotSlot.emptySlots(count: 3), weather: .clear))
        XCTAssertTrue(clear.filter { $0.name == GardenTileCatalog.rain }.isEmpty)
        let rainy = placements(snap(slots: GardenPlotSlot.emptySlots(count: 3), weather: .rain))
        XCTAssertFalse(rainy.filter { $0.name == GardenTileCatalog.rain }.isEmpty)
    }

    func testFencePerimeterComplete() {
        let fences = placements(snap(slots: GardenPlotSlot.emptySlots(count: 3)))
            .filter { $0.name.hasPrefix("fence_") }
        // perimeter of a 10×6 grid = 2*(10+6) - 4 = 28 cells
        XCTAssertEqual(fences.count, 28)
        XCTAssertTrue(fences.contains { $0.name == "fence_nw" && $0.col == 0 && $0.row == 0 })
        XCTAssertTrue(fences.contains { $0.name == "fence_se" && $0.col == 9 && $0.row == 5 })
    }

    func testCottageIsTwoByTwo() {
        let home = placements(snap(slots: GardenPlotSlot.emptySlots(count: 3)))
            .first { $0.name == GardenTileCatalog.home }
        XCTAssertEqual(home?.wTiles, 2)
        XCTAssertEqual(home?.hTiles, 2)
    }
}
