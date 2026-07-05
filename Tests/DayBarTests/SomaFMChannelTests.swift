import XCTest
@testable import DayBarCore

final class SomaFMChannelTests: XCTestCase {
    private let sampleJSON = """
    {
      "channels": [{
        "id": "groovesalad",
        "title": "Groove Salad",
        "description": "Downtempo",
        "genre": "ambient",
        "image": "https://example.com/s.png",
        "largeimage": "https://example.com/l.png",
        "dj": "Rusty",
        "playlists": [
          { "url": "https://api.somafm.com/groovesalad.pls", "format": "mp3", "quality": "highest" },
          { "url": "https://api.somafm.com/groovesalad130.pls", "format": "aac", "quality": "highest" },
          { "url": "https://api.somafm.com/groovesalad64.pls", "format": "aacp", "quality": "high" }
        ],
        "lastPlaying": "Artist - Track"
      }]
    }
    """

    func testDecodeChannel() throws {
        let data = Data(sampleJSON.utf8)
        let response = try JSONDecoder().decode(SomaFMChannelsResponse.self, from: data)
        XCTAssertEqual(response.channels.count, 1)
        XCTAssertEqual(response.channels[0].id, "groovesalad")
        XCTAssertEqual(response.channels[0].lastPlaying, "Artist - Track")
    }

    func testBestPlaylistPrefersAACOverMP3() throws {
        let data = Data(sampleJSON.utf8)
        let channel = try JSONDecoder().decode(SomaFMChannelsResponse.self, from: data).channels[0]
        XCTAssertTrue(channel.bestPlaylistURL?.absoluteString.contains("130.pls") == true)
        XCTAssertEqual(channel.orderedPlaylistURLs.count, 3)
        XCTAssertEqual(channel.orderedPlaylistURLs[0].absoluteString, "https://api.somafm.com/groovesalad130.pls")
    }
}
