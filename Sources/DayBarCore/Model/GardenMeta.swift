import Foundation
import SwiftData

/// Single-row garden progress. Focus sessions remain the source of truth for focus;
/// this row stores projection state (slots, coins, unlocks) for the Focus Garden.
@Model
public final class GardenMeta {
    public var lastSettledDay: Date?
    public var coins: Int = 0
    public var lifetimeCompletedSessions: Int = 0
    public var companionID: String = "default"
    public var unlockedItemIDsJSON: String = "[]"
    public var currentSeasonRaw: String = GardenSeason.spring.rawValue
    public var plotSlotsJSON: String = GardenMeta.defaultSlotsJSON
    public var harvestLogJSON: String = "[]"
    /// Last crop planted (drives Phase 2 rotation).
    public var lastPlantedCropID: String?
    /// Newest-first durable reward feed for the Garden HUD ribbon.
    public var rewardFeedJSON: String = "[]"
    /// Owned farm animals (JSON `[OwnedAnimal]`).
    public var animalsJSON: String = "[]"

    public init(
        lastSettledDay: Date? = nil,
        coins: Int = 0,
        lifetimeCompletedSessions: Int = 0,
        companionID: String = "default",
        unlockedItemIDsJSON: String = "[]",
        currentSeasonRaw: String = GardenSeason.spring.rawValue,
        plotSlotsJSON: String = GardenMeta.defaultSlotsJSON,
        harvestLogJSON: String = "[]",
        lastPlantedCropID: String? = nil,
        rewardFeedJSON: String = "[]",
        animalsJSON: String = "[]"
    ) {
        self.lastSettledDay = lastSettledDay
        self.coins = coins
        self.lifetimeCompletedSessions = lifetimeCompletedSessions
        self.companionID = companionID
        self.unlockedItemIDsJSON = unlockedItemIDsJSON
        self.currentSeasonRaw = currentSeasonRaw
        self.plotSlotsJSON = plotSlotsJSON
        self.harvestLogJSON = harvestLogJSON
        self.lastPlantedCropID = lastPlantedCropID
        self.rewardFeedJSON = rewardFeedJSON
        self.animalsJSON = animalsJSON
    }

    public static var defaultSlotsJSON: String {
        encodeSlots(GardenPlotSlot.emptySlots()) ?? "[]"
    }

    public var slots: [GardenPlotSlot] {
        get { Self.decodeSlots(plotSlotsJSON) }
        set { plotSlotsJSON = Self.encodeSlots(newValue) ?? GardenMeta.defaultSlotsJSON }
    }

    public var unlockedItemIDs: [String] {
        get { Self.decodeStringArray(unlockedItemIDsJSON) }
        set { unlockedItemIDsJSON = Self.encodeStringArray(newValue) ?? "[]" }
    }

    public var harvestLog: [GardenHarvestEntry] {
        get { Self.decodeHarvestLog(harvestLogJSON) }
        set { harvestLogJSON = Self.encodeHarvestLog(newValue) ?? "[]" }
    }

    public var recentRewards: [GardenRewardEntry] {
        get { Self.decodeRewardFeed(rewardFeedJSON) }
        set { rewardFeedJSON = Self.encodeRewardFeed(newValue) ?? "[]" }
    }

    public var animals: [OwnedAnimal] {
        get { Self.decodeAnimals(animalsJSON) }
        set { animalsJSON = Self.encodeAnimals(newValue) ?? "[]" }
    }

    public var season: GardenSeason {
        get { GardenSeason(rawValue: currentSeasonRaw) ?? .spring }
        set { currentSeasonRaw = newValue.rawValue }
    }

    public static func encodeSlots(_ slots: [GardenPlotSlot]) -> String? {
        guard let data = try? JSONEncoder().encode(slots) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeSlots(_ json: String) -> [GardenPlotSlot] {
        guard let data = json.data(using: .utf8),
              let slots = try? JSONDecoder().decode([GardenPlotSlot].self, from: data),
              !slots.isEmpty else {
            return GardenPlotSlot.emptySlots()
        }
        return slots.sorted { $0.index < $1.index }
    }

    public static func encodeStringArray(_ values: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(values) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    public static func encodeHarvestLog(_ log: [GardenHarvestEntry]) -> String? {
        guard let data = try? JSONEncoder().encode(log) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeHarvestLog(_ json: String) -> [GardenHarvestEntry] {
        guard let data = json.data(using: .utf8),
              let log = try? JSONDecoder().decode([GardenHarvestEntry].self, from: data) else {
            return []
        }
        return log
    }

    public static func encodeRewardFeed(_ feed: [GardenRewardEntry]) -> String? {
        guard let data = try? JSONEncoder().encode(feed) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeRewardFeed(_ json: String) -> [GardenRewardEntry] {
        guard let data = json.data(using: .utf8),
              let feed = try? JSONDecoder().decode([GardenRewardEntry].self, from: data) else {
            return []
        }
        return feed
    }

    public static func encodeAnimals(_ animals: [OwnedAnimal]) -> String? {
        guard let data = try? JSONEncoder().encode(animals) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeAnimals(_ json: String) -> [OwnedAnimal] {
        guard let data = json.data(using: .utf8),
              let animals = try? JSONDecoder().decode([OwnedAnimal].self, from: data) else {
            return []
        }
        return animals
    }
}
