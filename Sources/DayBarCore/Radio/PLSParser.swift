import Foundation

public enum PLSParserError: Error, Sendable {
    case invalidResponse
    case streamURLNotFound
}

/// Parses SomaFM `.pls` playlist files and caches resolved stream URLs on disk.
public enum PLSParser {
    private static let cacheTTL: TimeInterval = 7 * 24 * 3600

    public static var radioDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DayBar/radio", isDirectory: true)
    }

    public static func parseStreamURL(from plsText: String) throws -> URL {
        for line in plsText.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("file1=") else { continue }
            let value = trimmed.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: String(value)) else { continue }
            return url
        }
        throw PLSParserError.streamURLNotFound
    }

    public static func resolveStreamURL(
        playlistURL: URL,
        session: URLSession = .shared,
        now: Date = .now,
        fileManager: FileManager = .default
    ) async throws -> URL {
        if let cached = loadCachedStreamURL(for: playlistURL, now: now, fileManager: fileManager) {
            return cached
        }
        let (data, response) = try await session.data(from: playlistURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw PLSParserError.invalidResponse
        }
        let streamURL = try parseStreamURL(from: text)
        saveCachedStreamURL(streamURL, for: playlistURL, now: now, fileManager: fileManager)
        return streamURL
    }

    // MARK: - Disk cache

    private static func cacheFileURL(for playlistURL: URL, fileManager: FileManager) -> URL {
        let dir = radioDirectory.appendingPathComponent("pls-cache", isDirectory: true)
        let key = playlistURL.absoluteString
            .data(using: .utf8)
            .map { $0.base64EncodedString() }
            .map { $0.replacingOccurrences(of: "/", with: "_") } ?? "unknown"
        return dir.appendingPathComponent("\(key).json")
    }

    private struct CacheEntry: Codable {
        var streamURL: String
        var cachedAt: Date
    }

    static func loadCachedStreamURL(
        for playlistURL: URL,
        now: Date,
        fileManager: FileManager
    ) -> URL? {
        let fileURL = cacheFileURL(for: playlistURL, fileManager: fileManager)
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
              now.timeIntervalSince(entry.cachedAt) < cacheTTL,
              let url = URL(string: entry.streamURL) else {
            return nil
        }
        return url
    }

    private static func saveCachedStreamURL(
        _ streamURL: URL,
        for playlistURL: URL,
        now: Date,
        fileManager: FileManager
    ) {
        let dir = radioDirectory.appendingPathComponent("pls-cache", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let entry = CacheEntry(streamURL: streamURL.absoluteString, cachedAt: now)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        let fileURL = cacheFileURL(for: playlistURL, fileManager: fileManager)
        try? data.write(to: fileURL, options: .atomic)
    }
}
