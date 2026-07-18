import SwiftUI
import DayBarCore

/// Garden unlock shop, presented from the Garden tab / companion. Relocated from the retired
/// GardenDayscapeView; presentation stays owned by the panel root so the popover isn't torn down.
struct GardenShopSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var coins: Int { appState.gardenSnapshot?.coins ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Garden shop").font(.headline)
                Spacer()
                Label("\(coins)", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(coins) coins")
            }
            ForEach(GardenCatalog.shopItems) { item in
                let owned = appState.gardenSnapshot?.unlockedItemIDs.contains(item.id) ?? false
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if owned {
                        Text("Owned")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    } else {
                        Button {
                            _ = appState.purchaseGardenItem(item.id)
                        } label: {
                            Text("\(item.price)c").monospacedDigit()
                        }
                        .disabled(coins < item.price)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider().padding(.vertical, 2)
            HStack {
                Text("Animals").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(animalCount) / \(GardenAnimalCatalog.maxAnimals)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            ForEach(AnimalKind.allCases) { kind in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.displayName).font(.subheadline.weight(.medium))
                        Text("Produces \(kind.productName.lowercased()) every \(kind.productionEnergy) focus sessions · +\(kind.collectValue)c to collect")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        _ = appState.buyAnimal(kind)
                    } label: {
                        Text("\(kind.price)c").monospacedDigit()
                    }
                    .disabled(coins < kind.price || animalCount >= GardenAnimalCatalog.maxAnimals)
                }
                .padding(.vertical, 4)
            }

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 340)
    }

    private var animalCount: Int { appState.gardenSnapshot?.animals.count ?? 0 }
}
