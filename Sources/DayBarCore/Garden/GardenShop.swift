import Foundation

public enum GardenShop {
    public struct PurchaseResult: Sendable, Equatable {
        public var success: Bool
        public var itemID: String
        public var coinsRemaining: Int
        public var alreadyOwned: Bool

        public init(success: Bool, itemID: String, coinsRemaining: Int, alreadyOwned: Bool = false) {
            self.success = success
            self.itemID = itemID
            self.coinsRemaining = coinsRemaining
            self.alreadyOwned = alreadyOwned
        }
    }

    @discardableResult
    public static func purchase(itemID: String, meta: GardenMeta) -> PurchaseResult {
        guard let item = GardenCatalog.shopItems.first(where: { $0.id == itemID }) else {
            return PurchaseResult(success: false, itemID: itemID, coinsRemaining: meta.coins)
        }

        var unlocks = meta.unlockedItemIDs
        if unlocks.contains(itemID) {
            return PurchaseResult(
                success: false,
                itemID: itemID,
                coinsRemaining: meta.coins,
                alreadyOwned: true
            )
        }
        guard meta.coins >= item.price else {
            return PurchaseResult(success: false, itemID: itemID, coinsRemaining: meta.coins)
        }

        meta.coins -= item.price
        unlocks.append(itemID)
        meta.unlockedItemIDs = unlocks

        if itemID == GardenCatalog.itemExtraSlot {
            var slots = meta.slots
            if slots.count < GardenCatalog.maxSlotCount {
                slots.append(GardenPlotSlot(index: slots.count))
                meta.slots = slots
            }
        }

        return PurchaseResult(success: true, itemID: itemID, coinsRemaining: meta.coins)
    }

    public struct BuyAnimalResult: Sendable, Equatable {
        public var success: Bool
        public var kind: AnimalKind
        public var coinsRemaining: Int
        public var animalID: UUID?

        public init(success: Bool, kind: AnimalKind, coinsRemaining: Int, animalID: UUID? = nil) {
            self.success = success
            self.kind = kind
            self.coinsRemaining = coinsRemaining
            self.animalID = animalID
        }
    }

    /// Buy a farm animal: deducts the price, appends a fresh (not-yet-ready) `OwnedAnimal`, and assigns
    /// the first free pen cell. Fails (no mutation) if coins are short or the pen is full. A bought
    /// animal starts at `energyUntilReady = productionEnergy`, so it must be focus-fed before producing.
    @discardableResult
    public static func buyAnimal(kind: AnimalKind, meta: GardenMeta, asOf now: Date = .now) -> BuyAnimalResult {
        var animals = meta.animals
        guard meta.coins >= kind.price, animals.count < GardenAnimalCatalog.maxAnimals else {
            return BuyAnimalResult(success: false, kind: kind, coinsRemaining: meta.coins)
        }
        let used = Set(animals.compactMap(\.cell))
        let cell = (0..<GardenAnimalCatalog.maxAnimals).first { !used.contains($0) }
        let animal = OwnedAnimal(kind: kind, energyUntilReady: kind.productionEnergy, cell: cell, acquiredAt: now)
        animals.append(animal)
        meta.animals = animals
        meta.coins -= kind.price
        return BuyAnimalResult(success: true, kind: kind, coinsRemaining: meta.coins, animalID: animal.id)
    }
}
