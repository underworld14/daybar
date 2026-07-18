import SwiftUI
import DayBarCore

/// The dedicated Garden tab: reward HUD, the interactive farm canvas, and a recent-reward feed.
/// Harvest/plant intents route to AppState; the mode follows the Settings preference live.
struct GardenTabView: View {
    let snapshot: GardenSnapshot
    var onShop: () -> Void

    @Environment(AppState.self) private var appState
    @AppStorage(PreferenceKeys.gardenActionMode) private var actionMode: GardenActionMode = .automatic

    var body: some View {
        VStack(spacing: 10) {
            hud
            GardenFarmCanvas(
                snapshot: snapshot,
                mode: actionMode,
                onHarvest: { appState.harvestGardenSlot($0) },
                onPlant: { appState.plantGardenSlot($0) },
                onCompanion: onShop
            )
            rewardFeed
        }
        .frame(width: 320)
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                statTile("\(snapshot.coins)", "Coins", "circlebadge.fill", .orange)
                statTile("\(snapshot.currentStreak)d", "Streak", "flame.fill", .pink)
                statTile("\(readyCount)", "Ready", "leaf.fill", .green)
            }
            if let n = nextUnlock { nextUnlockBar(n) }
        }
    }

    private func statTile(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Label(value, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func nextUnlockBar(_ n: (title: String, price: Int)) -> some View {
        let have = min(snapshot.coins, n.price)
        return VStack(spacing: 3) {
            HStack {
                Text("Next unlock").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(have) / \(n.price) · \(n.title)")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(have), total: Double(max(1, n.price)))
                .tint(.orange)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next unlock \(n.title): \(have) of \(n.price) coins")
    }

    // MARK: reward feed

    private var rewardFeed: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Recent rewards")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onShop) {
                    Label("Shop", systemImage: "bag.fill").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            }
            if snapshot.recentRewards.isEmpty {
                Text("Finish a focus session to grow your garden.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.recentRewards.prefix(3)) { entry in
                    HStack(spacing: 6) {
                        Circle().fill(.orange).frame(width: 5, height: 5)
                        Text(entry.text).font(.caption2).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entry.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: derived

    private var readyCount: Int { snapshot.slots.filter(\.isMature).count }

    private var nextUnlock: (title: String, price: Int)? {
        GardenCatalog.shopItems
            .sorted { $0.price < $1.price }
            .first { !snapshot.unlockedItemIDs.contains($0.id) }
            .map { ($0.title, $0.price) }
    }
}
