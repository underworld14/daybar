import Foundation

public enum SomaFMCuratedChannels {
    /// All curated stations shown in the Menu picker (~15).
    public static let curatedAllIDs: [String] = [
        "groovesalad",
        "groovesalad2",
        "gsclassic",
        "beatblender",
        "dronezone",
        "dz2",
        "deepspaceone",
        "spacestation",
        "fluid",
        "defcon",
        "lush",
        "sonicuniverse",
        "thetrip",
        "synphaera",
        "n5md",
        "vaporwaves",
    ]

    /// Stations cycled by ⏮/⏭ — excludes redundant Groove Salad variants (~12).
    public static let curatedSkipIDs: [String] = [
        "groovesalad",
        "beatblender",
        "dronezone",
        "dz2",
        "deepspaceone",
        "spacestation",
        "fluid",
        "defcon",
        "lush",
        "sonicuniverse",
        "thetrip",
        "synphaera",
        "n5md",
        "vaporwaves",
    ]

    public enum Direction: Sendable {
        case next
        case previous
    }

    public static func filterAll(_ channels: [SomaFMChannel]) -> [SomaFMChannel] {
        filter(channels, orderedIDs: curatedAllIDs)
    }

    public static func filterSkip(_ channels: [SomaFMChannel]) -> [SomaFMChannel] {
        filter(channels, orderedIDs: curatedSkipIDs)
    }

    /// Maps picker-only Groove Salad variants to the skip-list anchor station.
    private static let skipAnchorIDs: [String: String] = [
        "groovesalad2": "groovesalad",
        "gsclassic": "groovesalad",
    ]

    public static func adjacentChannel(
        from current: SomaFMChannel?,
        in channels: [SomaFMChannel],
        direction: Direction
    ) -> SomaFMChannel? {
        guard !channels.isEmpty else { return nil }
        let lookupID: String
        if let current {
            lookupID = skipAnchorIDs[current.id] ?? current.id
        } else {
            lookupID = channels[0].id
        }
        let currentIndex = channels.firstIndex(where: { $0.id == lookupID }) ?? 0
        let delta = direction == .next ? 1 : -1
        let nextIndex = (currentIndex + delta + channels.count) % channels.count
        return channels[nextIndex]
    }

    private static func filter(_ channels: [SomaFMChannel], orderedIDs: [String]) -> [SomaFMChannel] {
        let byID = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        return orderedIDs.compactMap { byID[$0] }
    }
}
