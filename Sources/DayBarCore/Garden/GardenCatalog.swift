import Foundation

public enum GardenCatalog {
    public static let maxStage = 4
    public static let defaultSlotCount = 3
    public static let maxSlotCount = 4
    public static let defaultCropID = "parsnip"
    public static let cropRotation = ["parsnip", "cauliflower", "berry"]

    public static let itemSeedPack = "seed_pack"
    public static let itemFence = "fence"
    public static let itemScarf = "scarf"
    public static let itemExtraSlot = "extra_slot"

    public struct ShopItem: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let price: Int
        public let detail: String

        public init(id: String, title: String, price: Int, detail: String) {
            self.id = id
            self.title = title
            self.price = price
            self.detail = detail
        }
    }

    public static let shopItems: [ShopItem] = [
        ShopItem(id: itemSeedPack, title: "Seed pack", price: 5, detail: "Bias new plants toward berries"),
        ShopItem(id: itemFence, title: "Garden fence", price: 8, detail: "Cozy border around the plots"),
        ShopItem(id: itemScarf, title: "Companion scarf", price: 12, detail: "A warm scarf for your friend"),
        ShopItem(id: itemExtraSlot, title: "Extra plot", price: 20, detail: "Unlock a fourth garden bed"),
    ]

    public static func displayName(for cropID: String) -> String {
        switch cropID {
        case "parsnip": return "Parsnip"
        case "cauliflower": return "Cauliflower"
        case "berry": return "Berry"
        default: return cropID.capitalized
        }
    }

    public static func nextCropID(after lastCropID: String?, unlocked: [String]) -> String {
        if unlocked.contains(itemSeedPack) {
            return "berry"
        }
        guard let last = lastCropID, let idx = cropRotation.firstIndex(of: last) else {
            return defaultCropID
        }
        return cropRotation[(idx + 1) % cropRotation.count]
    }
}
