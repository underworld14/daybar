import Foundation

/// Static catalog for buyable farm animals. Animals are multi-instance (unlike the boolean shop
/// unlocks in `GardenCatalog`), so they live in their own owned collection on `GardenMeta`.
public enum GardenAnimalCatalog {
    /// Pen capacity. The farm scene must expose at least this many pen cells.
    public static let maxAnimals = 4

    /// Shop rows for the animal aisle, derived from `AnimalKind` so pricing stays in one place.
    public static var shopItems: [GardenCatalog.ShopItem] {
        AnimalKind.allCases.map { kind in
            GardenCatalog.ShopItem(
                id: kind.spriteBase,
                title: kind.displayName,
                price: kind.price,
                detail: "Produces \(kind.productName.lowercased()) as you focus"
            )
        }
    }

    /// The `AnimalKind` for a shop-item id (`animal_chicken` → `.chicken`), or `nil`.
    public static func kind(forItemID id: String) -> AnimalKind? {
        AnimalKind.allCases.first { $0.spriteBase == id }
    }
}
