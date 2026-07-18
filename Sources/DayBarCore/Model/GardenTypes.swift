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

/// How completed-session energy drives plots. `automatic` (default) plants empty plots and harvests
/// mature crops as focus energy arrives; `manual` grows crops but leaves harvest/plant to the player.
public enum GardenActionMode: String, Codable, Sendable, CaseIterable {
    case automatic, manual
}

/// Panel-level navigation for the menu popover.
public enum PanelTab: String, Codable, Sendable, CaseIterable {
    case today, garden
}

/// A durable, human-readable record of what a focus session (or manual action) gave the garden.
/// `seq` is a deterministic monotonically-increasing id (newest = highest) so SwiftUI `ForEach`
/// identity is stable without relying on nondeterministic UUIDs.
public struct GardenRewardEntry: Codable, Sendable, Equatable, Identifiable {
    public var seq: Int
    public var date: Date
    public var text: String
    public var coinDelta: Int
    public var kindRaw: String
    public var cropID: String?

    public var id: Int { seq }

    public enum Kind: String, Codable, Sendable {
        case coin, grew, planted, harvested, animalReady, collected
    }

    public var kind: Kind { Kind(rawValue: kindRaw) ?? .coin }

    public init(
        seq: Int,
        date: Date,
        text: String,
        coinDelta: Int,
        kind: Kind,
        cropID: String? = nil
    ) {
        self.seq = seq
        self.date = date
        self.text = text
        self.coinDelta = coinDelta
        self.kindRaw = kind.rawValue
        self.cropID = cropID
    }
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

/// A kind of farm animal you can buy. Animals produce a collectible ONLY as completed focus sessions
/// arrive (never on idle/real time) — every coin still traces back to focus. Prices sit at/above the
/// top shop tier so animals are aspirational; marginal coins/session stays below the guaranteed
/// 1 coin/session from focus itself, so an animal is a long-term investment, not an idle earner.
public enum AnimalKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case chicken, cow, sheep

    public var id: String { rawValue }

    /// Coin cost in the shop.
    public var price: Int {
        switch self {
        case .chicken: return 10
        case .cow: return 20
        case .sheep: return 30
        }
    }

    /// Completed focus sessions needed to grow one product.
    public var productionEnergy: Int {
        switch self {
        case .chicken: return 3
        case .cow: return 6
        case .sheep: return 8
        }
    }

    /// Coins awarded when the ready product is collected.
    public var collectValue: Int {
        switch self {
        case .chicken: return 2
        case .cow: return 5
        case .sheep: return 7
        }
    }

    public var productName: String {
        switch self {
        case .chicken: return "Egg"
        case .cow: return "Milk"
        case .sheep: return "Wool"
        }
    }

    public var displayName: String {
        switch self {
        case .chicken: return "Chicken"
        case .cow: return "Cow"
        case .sheep: return "Sheep"
        }
    }

    /// Base sprite name; `_idle`/`_ready` variants render the current state.
    public var spriteBase: String { "animal_\(rawValue)" }
}

/// A single owned animal instance. `energyUntilReady` counts DOWN as completed-session energy arrives;
/// at `<= 0` the animal has a product to collect. Collecting resets it to `kind.productionEnergy`.
public struct OwnedAnimal: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kindRaw: String
    public var energyUntilReady: Int
    /// Pen-cell INDEX in the farm scene (0..<maxAnimals); `nil` = unplaced.
    public var cell: Int?
    public var acquiredAt: Date

    public var kind: AnimalKind { AnimalKind(rawValue: kindRaw) ?? .chicken }
    public var hasProduct: Bool { energyUntilReady <= 0 }

    public init(
        id: UUID = UUID(),
        kind: AnimalKind,
        energyUntilReady: Int,
        cell: Int? = nil,
        acquiredAt: Date
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.energyUntilReady = energyUntilReady
        self.cell = cell
        self.acquiredAt = acquiredAt
    }
}

/// Derived, UI-facing view of an owned animal (not persisted; rebuilt each settle).
public struct AnimalSnapshot: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: AnimalKind
    public var cell: Int?
    public var hasProduct: Bool
    public var energyUntilReady: Int

    public init(id: UUID, kind: AnimalKind, cell: Int?, hasProduct: Bool, energyUntilReady: Int) {
        self.id = id
        self.kind = kind
        self.cell = cell
        self.hasProduct = hasProduct
        self.energyUntilReady = energyUntilReady
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
    /// Newest-first durable reward feed for the Garden HUD ribbon.
    public var recentRewards: [GardenRewardEntry]
    /// Owned farm animals with their current ready/energy state (for the roaming farm scene + HUD).
    public var animals: [AnimalSnapshot]

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
        hasScarf: Bool = false,
        recentRewards: [GardenRewardEntry] = [],
        animals: [AnimalSnapshot] = []
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
        self.recentRewards = recentRewards
        self.animals = animals
    }
}
