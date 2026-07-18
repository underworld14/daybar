import SwiftUI
import DayBarCore

/// Focus garden row that replaces the Dayscape ink strip in the Today panel.
struct GardenDayscapeView: View {
    let snapshot: GardenSnapshot
    var onShop: (() -> Void)?
    var harvestCaption: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stripHeight: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    GardenRenderer.PixelImage(
                        name: GardenRenderer.skyName(for: snapshot.season),
                        width: stripWidth,
                        height: stripHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if snapshot.weather == .rain {
                        GardenRenderer.PixelImage(
                            name: "weather_rain",
                            width: stripWidth,
                            height: stripHeight
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .opacity(reduceMotion ? 0.5 : 0.85)
                        .allowsHitTesting(false)
                    }

                    HStack(alignment: .bottom, spacing: 4) {
                        if snapshot.hasFence {
                            GardenRenderer.FenceView()
                        }
                        ForEach(snapshot.slots) { slot in
                            GardenRenderer.PlotView(
                                slot: slot,
                                season: snapshot.season,
                                reduceMotion: reduceMotion
                            )
                        }
                        if snapshot.hasFence {
                            GardenRenderer.FenceView()
                        }
                        Button {
                            onShop?()
                        } label: {
                            GardenRenderer.CompanionView(
                                mood: snapshot.companionMood,
                                hasScarf: snapshot.hasScarf,
                                reduceMotion: reduceMotion
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Open garden shop")
                        .accessibilityHint("Opens the garden shop")
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
                }
                .frame(height: stripHeight)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    if snapshot.currentStreak > 0 {
                        Text("\(snapshot.currentStreak)d")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .help(graceHelp)
                            .accessibilityLabel("Focus streak \(snapshot.currentStreak) days")
                    }
                    Text("\(snapshot.coins)c")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(snapshot.coins) garden coins")
                }
            }

            if let harvestCaption, !harvestCaption.isEmpty {
                Text(harvestCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if snapshot.harvestThisWeek > 0 {
                Text("Harvests this week: \(snapshot.harvestThisWeek)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus garden, \(snapshot.season.rawValue)")
    }

    /// Wide enough for 3–4 plots + companion + optional fences.
    private var stripWidth: CGFloat {
        let plots = CGFloat(snapshot.slots.count)
        let plotW: CGFloat = 32 * GardenRenderer.pixelScale
        let companion: CGFloat = 32 * GardenRenderer.pixelScale
        let fence: CGFloat = snapshot.hasFence ? 12 * GardenRenderer.pixelScale * 2 : 0
        let gaps = 4 * (plots + 2)
        return max(240, plots * plotW + companion + fence + gaps + 24)
    }

    private var graceHelp: String {
        if snapshot.graceRemaining > 0 {
            return "\(snapshot.graceRemaining) grace day left this week"
        }
        return "No grace days left this week"
    }
}

/// Simple shop sheet for garden unlocks.
struct GardenShopSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Garden shop")
                    .font(.headline)
                Spacer()
                Text("\(appState.gardenSnapshot?.coins ?? 0) coins")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(GardenCatalog.shopItems) { item in
                let owned = appState.gardenSnapshot?.unlockedItemIDs.contains(item.id) ?? false
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if owned {
                        Text("Owned").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("\(item.price)c") {
                            _ = appState.purchaseGardenItem(item.id)
                        }
                        .disabled((appState.gardenSnapshot?.coins ?? 0) < item.price)
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
