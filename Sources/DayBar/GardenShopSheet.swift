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
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 320)
    }
}
