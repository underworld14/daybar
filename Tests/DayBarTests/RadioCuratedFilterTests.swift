import XCTest
@testable import DayBarCore

final class RadioCuratedFilterTests: XCTestCase {
    private func channel(id: String) -> SomaFMChannel {
        SomaFMChannel(
            id: id,
            title: id,
            description: "",
            genre: "ambient",
            image: "",
            largeimage: "",
            dj: "",
            playlists: [],
            lastPlaying: nil
        )
    }

    func testFilterAllPreservesCuratedOrder() {
        let input = ["vaporwaves", "groovesalad", "dronezone"].map(channel(id:))
        let filtered = SomaFMCuratedChannels.filterAll(input)
        XCTAssertEqual(filtered.map(\.id), ["groovesalad", "dronezone", "vaporwaves"])
    }

    func testAdjacentChannelWrapsForward() {
        let list = ["a", "b", "c"].map(channel(id:))
        let next = SomaFMCuratedChannels.adjacentChannel(from: list[2], in: list, direction: .next)
        XCTAssertEqual(next?.id, "a")
    }

    func testAdjacentChannelWrapsBackward() {
        let list = ["a", "b", "c"].map(channel(id:))
        let prev = SomaFMCuratedChannels.adjacentChannel(from: list[0], in: list, direction: .previous)
        XCTAssertEqual(prev?.id, "c")
    }

    func testSkipListExcludesGrooveSaladVariants() {
        let ids = SomaFMCuratedChannels.filterSkip(
            SomaFMCuratedChannels.curatedAllIDs.map(channel(id:))
        ).map(\.id)
        XCTAssertTrue(ids.contains("groovesalad"))
        XCTAssertFalse(ids.contains("groovesalad2"))
        XCTAssertFalse(ids.contains("gsclassic"))
    }

    func testAdjacentFromGrooveSaladVariantUsesAnchor() {
        let list = SomaFMCuratedChannels.curatedSkipIDs.prefix(4).map(channel(id:))
        let gs2 = channel(id: "groovesalad2")
        let next = SomaFMCuratedChannels.adjacentChannel(from: gs2, in: Array(list), direction: .next)
        XCTAssertEqual(next?.id, "beatblender")
    }
}
