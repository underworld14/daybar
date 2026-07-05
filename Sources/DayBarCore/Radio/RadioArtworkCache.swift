import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Disk cache for SomaFM channel artwork keyed by channel id.
public actor RadioArtworkCache {
    private let session: URLSession
    private let fileManager: FileManager

    public init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    public func imageData(for channel: SomaFMChannel) async -> Data? {
        let fileURL = artworkFileURL(for: channel.id)
        if let data = try? Data(contentsOf: fileURL) {
            return data
        }
        guard let remoteURL = URL(string: channel.largeimage.isEmpty ? channel.image : channel.largeimage) else {
            return nil
        }
        do {
            let (data, response) = try await session.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            try? fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
            return data
        } catch {
            print("DayBar: artwork download failed for \(channel.id): \(error)")
            return nil
        }
    }

    #if canImport(AppKit)
    @MainActor
    public static func image(from data: Data?) -> NSImage? {
        guard let data else { return nil }
        return NSImage(data: data)
    }
    #endif

    private var artworkDirectory: URL {
        PLSParser.radioDirectory.appendingPathComponent("artwork", isDirectory: true)
    }

    private func artworkFileURL(for channelID: String) -> URL {
        artworkDirectory.appendingPathComponent("\(channelID).img")
    }
}
