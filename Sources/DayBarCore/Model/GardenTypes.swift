import Foundation

public enum GardenSeason: String, Codable, Sendable, CaseIterable {
    case spring, summer, autumn, winter

    public static func from(month: Int) -> GardenSeason {
        switch month {
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        case 9, 10, 11: return .autumn
        default: return .winter
        }
    }

    /// Crops that receive seasonal growth bonus (Phase 3).
    public var favoredCropIDs: Set<String> {
        switch self {
        case .spring: return ["parsnip"]
        case .summer: return ["berry"]
        case .autumn: return ["cauliflower"]
        case .winter: return ["parsnip"]
        }
    }
}

public enum CompanionMood: String, Codable, Sendable {
    case idle, happy, wilted
}

public enum GardenWeather: String, Codable, Sendable {
    case clear, rain
}

public struct GardenPlotSlot: Codable, Sendable, Equatable, Identifiable {
    public var index: Int
    public var cropID: String?
    public var stage: Int
    public var plantedOn: Date?
    public var lastGrownOn: Date?
    public var wiltLevel: Int

    public var id: Int { index }

    public var isEmpty: Bool { cropID == nil || stage <= 0 }
    public var isMature: Bool { cropID != nil && stage >= GardenCatalog.maxStage }

    public init(
        index: Int,
        cropID: String? = nil,
        stage: Int = 0,
        plantedOn: Date? = nil,
        lastGrownOn: Date? = nil,
        wiltLevel: Int = 0
    ) {
        self.index = index
        self.cropID = cropID
        self.stage = stage
        self.plantedOn = plantedOn
        self.lastGrownOn = lastGrownOn
        self.wiltLevel = wiltLevel
    }

    public static func emptySlots(count: Int = GardenCatalog.defaultSlotCount) -> [GardenPlotSlot] {
        (0..<count).map { GardenPlotSlot(index: $0) }
    }
}

public struct GardenHarvestEntry: Codable, Sendable, Equatable {
    public var day: Date
    public var cropID: String
    public var count: Int

    public init(day: Date, cropID: String, count: Int = 1) {
        self.day = day
        self.cropID = cropID
        self.count = count
    }
}

public struct GardenSnapshot: Sendable, Equatable {
    public var slots: [GardenPlotSlot]
    public var companionMood: CompanionMood
    public var season: GardenSeason
    public var coins: Int
    public var currentStreak: Int
    public var graceRemaining: Int
    public var weather: GardenWeather
    public var unlockedItemIDs: [String]
    public var harvestThisWeek: Int
    public var justHarvestedCropID: String?
    public var hasFence: Bool
    public var hasScarf: Bool

    public init(
        slots: [GardenPlotSlot],
        companionMood: CompanionMood,
        season: GardenSeason,
        coins: Int,
        currentStreak: Int,
        graceRemaining: Int,
        weather: GardenWeather = .clear,
        unlockedItemIDs: [String] = [],
        harvestThisWeek: Int = 0,
        justHarvestedCropID: String? = nil,
        hasFence: Bool = false,
        hasScarf: Bool = false
    ) {
        self.slots = slots
        self.companionMood = companionMood
        self.season = season
        self.coins = coins
        self.currentStreak = currentStreak
        self.graceRemaining = graceRemaining
        self.weather = weather
        self.unlockedItemIDs = unlockedItemIDs
        self.harvestThisWeek = harvestThisWeek
        self.justHarvestedCropID = justHarvestedCropID
        self.hasFence = hasFence
        self.hasScarf = hasScarf
    }
}
