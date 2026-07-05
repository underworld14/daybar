import Foundation

public enum SomaFMError: Error, Sendable {
    case noDataAvailable
    case streamURLUnavailable
}

/// Fetches SomaFM channel metadata, caches `channels.json` on disk, and resolves stream URLs.
public actor SomaFMService {
    public static let channelsURL = URL(string: "https://somafm.com/channels.json")!

    private let session: URLSession
    private let fileManager: FileManager
    private let cacheTTL: TimeInterval

    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        cacheTTL: TimeInterval = 24 * 3600
    ) {
        self.session = session
        self.fileManager = fileManager
        self.cacheTTL = cacheTTL
    }

    public func fetchCuratedChannels(now: Date = .now) async throws -> [SomaFMChannel] {
        let all = try await fetchAllChannels(now: now)
        return SomaFMCuratedChannels.filterAll(all)
    }

    public func fetchAllChannels(now: Date = .now) async throws -> [SomaFMChannel] {
        if isCacheFresh(now: now), let cached = loadCachedChannels() {
            refreshCacheInBackground(now: now)
            return cached
        }
        do {
            let channels = try await downloadChannels()
            saveCachedChannels(channels, fetchedAt: now)
            return channels
        } catch {
            if let cached = loadCachedChannels() {
                return cached
            }
            throw SomaFMError.noDataAvailable
        }
    }

    public func resolveStreamURL(for channel: SomaFMChannel) async throws -> URL {
        for playlistURL in channel.orderedPlaylistURLs {
            do {
                return try await PLSParser.resolveStreamURL(
                    playlistURL: playlistURL,
                    session: session,
                    fileManager: fileManager
                )
            } catch {
                continue
            }
        }
        throw SomaFMError.streamURLUnavailable
    }

    public func prefetchStreamURLs(for channels: [SomaFMChannel]) async {
        for channel in channels {
            _ = try? await resolveStreamURL(for: channel)
        }
    }

    public func channel(withID id: String, now: Date = .now) async -> SomaFMChannel? {
        let channels = (try? await fetchCuratedChannels(now: now)) ?? []
        return channels.first { $0.id == id }
    }

    // MARK: - Cache paths

    private var radioDirectory: URL { PLSParser.radioDirectory }

    private var channelsFileURL: URL {
        radioDirectory.appendingPathComponent("channels.json")
    }

    private var channelsMetaURL: URL {
        radioDirectory.appendingPathComponent("channels.meta.json")
    }

    private struct ChannelsMeta: Codable {
        var fetchedAt: Date
    }

    /// Cache TTL check extracted for unit tests.
    public static func isCacheFresh(fetchedAt: Date, now: Date, ttl: TimeInterval) -> Bool {
        now.timeIntervalSince(fetchedAt) < ttl
    }

    private func isCacheFresh(now: Date) -> Bool {
        guard let meta = loadMeta() else { return false }
        return Self.isCacheFresh(fetchedAt: meta.fetchedAt, now: now, ttl: cacheTTL)
    }

    private func loadMeta() -> ChannelsMeta? {
        guard let data = try? Data(contentsOf: channelsMetaURL) else { return nil }
        return try? JSONDecoder().decode(ChannelsMeta.self, from: data)
    }

    private func loadCachedChannels() -> [SomaFMChannel]? {
        guard let data = try? Data(contentsOf: channelsFileURL),
              let response = try? JSONDecoder().decode(SomaFMChannelsResponse.self, from: data) else {
            return nil
        }
        return response.channels
    }

    private func saveCachedChannels(_ channels: [SomaFMChannel], fetchedAt: Date) {
        try? fileManager.createDirectory(at: radioDirectory, withIntermediateDirectories: true)
        let response = SomaFMChannelsResponse(channels: channels)
        if let data = try? JSONEncoder().encode(response) {
            try? data.write(to: channelsFileURL, options: .atomic)
        }
        let meta = ChannelsMeta(fetchedAt: fetchedAt)
        if let metaData = try? JSONEncoder().encode(meta) {
            try? metaData.write(to: channelsMetaURL, options: .atomic)
        }
    }

    private func downloadChannels() async throws -> [SomaFMChannel] {
        let (data, response) = try await session.data(from: Self.channelsURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SomaFMChannelsResponse.self, from: data)
        return decoded.channels
    }

    private func refreshCacheInBackground(now: Date) {
        Task {
            if let channels = try? await downloadChannels() {
                saveCachedChannels(channels, fetchedAt: now)
            }
        }
    }
}
