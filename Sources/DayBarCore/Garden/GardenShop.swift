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
}
