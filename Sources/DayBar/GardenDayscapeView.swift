import SwiftUI
import DayBarCore

/// Focus garden row that replaces the Dayscape ink strip in the Today panel.
struct GardenDayscapeView: View {
    let snapshot: GardenSnapshot
    var onShop: (() -> Void)?
    var harvestCaption: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(GardenRenderer.seasonSky(snapshot.season))
                        .frame(height: 44)
                        .overlay {
                            if snapshot.weather == .rain, !reduceMotion {
                                RainDots()
                            } else if snapshot.weather == .rain {
                                Color.blue.opacity(0.08)
                            }
                        }

                    HStack(alignment: .bottom, spacing: 6) {
                        if snapshot.hasFence {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.brown.opacity(0.55))
                                .frame(width: 3, height: 22)
                        }
                        ForEach(snapshot.slots) { slot in
                            GardenRenderer.PlotView(
                                slot: slot,
                                season: snapshot.season,
                                reduceMotion: reduceMotion
                            )
                        }
                        if snapshot.hasFence {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.brown.opacity(0.55))
                                .frame(width: 3, height: 22)
                        }
                        Button {
                            onShop?()
                        } label: {
                            GardenRenderer.CompanionView(
                                mood: snapshot.companionMood,
                                hasScarf: snapshot.hasScarf,
                                season: snapshot.season,
                                reduceMotion: reduceMotion
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Open garden shop")
                        .accessibilityHint("Opens the garden shop")
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }

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

    private var graceHelp: String {
        if snapshot.graceRemaining > 0 {
            return "\(snapshot.graceRemaining) grace day left this week"
        }
        return "No grace days left this week"
    }
}

private struct RainDots: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<12 {
                let x = CGFloat((i * 17) % Int(size.width))
                let y = CGFloat((i * 11) % Int(max(size.height, 1)))
                let rect = CGRect(x: x, y: y, width: 1.5, height: 4)
                context.fill(Path(ellipseIn: rect), with: .color(.blue.opacity(0.25)))
            }
        }
        .allowsHitTesting(false)
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
