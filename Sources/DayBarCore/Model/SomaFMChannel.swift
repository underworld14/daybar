import Foundation

public struct SomaFMChannelsResponse: Codable, Sendable {
    public let channels: [SomaFMChannel]
}

public struct SomaFMChannel: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let genre: String
    public let image: String
    public let largeimage: String
    public let dj: String
    public let playlists: [SomaFMPlaylist]
    public let lastPlaying: String?

    public struct SomaFMPlaylist: Codable, Sendable, Equatable {
        public let url: String
        public let format: String
        public let quality: String
    }

    /// Ordered playlist URLs: AAC highest first, then MP3, then AAC+ by quality.
    public var orderedPlaylistURLs: [URL] {
        let formatRank: [String: Int] = ["aac": 0, "mp3": 1, "aacp": 2]
        let qualityRank: [String: Int] = ["highest": 0, "high": 1, "low": 2]
        return playlists
            .sorted { lhs, rhs in
                let lf = formatRank[lhs.format] ?? 99
                let rf = formatRank[rhs.format] ?? 99
                if lf != rf { return lf < rf }
                let lq = qualityRank[lhs.quality] ?? 99
                let rq = qualityRank[rhs.quality] ?? 99
                return lq < rq
            }
            .compactMap { URL(string: $0.url) }
    }

    public var bestPlaylistURL: URL? { orderedPlaylistURLs.first }
}
