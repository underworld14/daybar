import SwiftUI
import DayBarCore

/// Root of the pop-out Garden window: a reward HUD, the roaming SpriteKit farm, and a footer with the
/// latest reward + an accessible Actions menu (so keyboard/VoiceOver users get every action without
/// click-to-move). The garden action mode follows the Settings preference live.
struct FarmWindowRoot: View {
    @Environment(AppState.self) private var appState
    @AppStorage(PreferenceKeys.gardenActionMode) private var mode: GardenActionMode = .automatic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showShop = false
    @State private var infoText: String?

    var body: some View {
        Group {
            if let snap = appState.gardenSnapshot {
                content(snap)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .sheet(isPresented: $showShop) { GardenShopSheet().environment(appState) }
        .alert("Plot", isPresented: Binding(get: { infoText != nil }, set: { if !$0 { infoText = nil } })) {
            Button("OK", role: .cancel) { infoText = nil }
        } message: {
            Text(infoText ?? "")
        }
    }

    private func content(_ snap: GardenSnapshot) -> some View {
        VStack(spacing: 0) {
            hudBar(snap)
            FarmSceneView(snapshot: snap, mode: mode, reduceMotion: reduceMotion, onIntent: handle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Roaming farm. \(readyCrops(snap)) crops and \(readyAnimals(snap)) animals ready. Use the Actions menu below to harvest, plant, and collect.")
            footer(snap)
        }
    }

    // MARK: - HUD

    private func hudBar(_ snap: GardenSnapshot) -> some View {
        HStack(spacing: 14) {
            stat("\(snap.coins)", "Coins", "circlebadge.fill", .orange)
            stat("\(snap.currentStreak)d", "Streak", "flame.fill", .pink)
            stat("\(readyCrops(snap))", "Crops", "leaf.fill", .green)
            stat("\(readyAnimals(snap))", "Animals", "pawprint.fill", .brown)
            Spacer()
            Text(mode == .manual ? "Manual" : "Auto")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            Button { showShop = true } label: { Label("Shop", systemImage: "bag.fill") }
                .accessibilityLabel("Open garden shop")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.headline).monospacedDigit()
                Text(label.uppercased()).font(.system(size: 9, weight: .medium)).tracking(0.5)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: - Footer

    private func footer(_ snap: GardenSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.caption).foregroundStyle(.orange)
            Text(snap.recentRewards.first?.text ?? "Click the ground to stroll; walk up to a plot or animal to interact.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            actionsMenu(snap)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
    }

    private func actionsMenu(_ snap: GardenSnapshot) -> some View {
        Menu {
            if mode == .manual {
                ForEach(Array(snap.slots.enumerated()), id: \.offset) { i, slot in
                    if slot.isMature {
                        Button("Harvest plot \(i + 1)") { appState.harvestGardenSlot(i) }
                    } else if slot.isEmpty {
                        Button("Plant plot \(i + 1)") { appState.plantGardenSlot(i) }
                    }
                }
            }
            ForEach(snap.animals.filter(\.hasProduct)) { a in
                Button("Collect \(a.kind.productName.lowercased()) from \(a.kind.displayName.lowercased())") {
                    appState.collectFromAnimal(a.id)
                }
            }
            Divider()
            Button("Shop…") { showShop = true }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Harvest, plant, and collect without the mouse")
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Complete a focus session to grow your garden.")
                .font(.title3).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Intents

    private func handle(_ intent: FarmIntent) {
        switch intent {
        case .harvest(let i): appState.harvestGardenSlot(i)
        case .plant(let i): appState.plantGardenSlot(i)
        case .collectAnimal(let id): appState.collectFromAnimal(id)
        case .openShop: showShop = true
        case .plotInfo(let i): infoText = plotInfoText(i)
        }
    }

    private func plotInfoText(_ i: Int) -> String {
        guard let snap = appState.gardenSnapshot, snap.slots.indices.contains(i) else { return "" }
        let slot = snap.slots[i]
        if slot.isEmpty { return "Plot \(i + 1) is empty. Completed focus sessions plant here automatically." }
        let name = GardenCatalog.displayName(for: slot.cropID ?? "")
        if slot.isMature { return "\(name) in plot \(i + 1) is ready. In Manual mode you'd harvest it here." }
        return "\(name) growing in plot \(i + 1) — stage \(slot.stage) of \(GardenCatalog.maxStage)."
            + (slot.wiltLevel > 0 ? " A little wilted; focus today to revive it." : "")
    }

    private func readyCrops(_ snap: GardenSnapshot) -> Int { snap.slots.filter(\.isMature).count }
    private func readyAnimals(_ snap: GardenSnapshot) -> Int { snap.animals.filter(\.hasProduct).count }
}
