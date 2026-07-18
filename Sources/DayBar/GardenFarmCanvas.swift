import SwiftUI
import DayBarCore

/// The interactive top-down farm scene. Renders the fixed 10×6 grid from `GardenSceneModel`
/// at a 32pt integer cell (320×192pt), then overlays accessible plot + companion controls.
///
/// - Manual mode: mature plots act as **Harvest**, empty plots as **Plant** (highlighted).
/// - Automatic mode: tapping a plot opens an informational popover (never mutates state).
/// Motion (companion bob, ready sparkle) honors Reduce Motion.
struct GardenFarmCanvas: View {
    let snapshot: GardenSnapshot
    let mode: GardenActionMode
    var onHarvest: (Int) -> Void
    var onPlant: (Int) -> Void
    var onCompanion: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var bob = false
    @State private var infoSlot: Int?

    private let cell: CGFloat = 32

    private var sceneW: CGFloat { CGFloat(GardenSceneModel.cols) * cell }
    private var sceneH: CGFloat { CGFloat(GardenSceneModel.rows) * cell }
    private var placements: [GardenTilePlacement] { GardenSceneModel.placements(for: snapshot) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(placements.enumerated()), id: \.offset) { _, p in
                if !p.name.hasPrefix("companion_") { tile(p) }
            }
            ForEach(Array(GardenSceneModel.plotCells.prefix(snapshot.slots.count).enumerated()), id: \.offset) { i, c in
                plotButton(i, at: c)
            }
            companionButton
        }
        .frame(width: sceneW, height: sceneH)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
        )
        .onAppear(perform: startAnimations)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus garden, \(snapshot.season.rawValue), \(readyCount) crops ready")
    }

    // MARK: tiles

    @ViewBuilder private func tile(_ p: GardenTilePlacement) -> some View {
        let w = CGFloat(p.wTiles) * cell
        let h = CGFloat(p.hTiles) * cell
        let isSparkle = p.name == GardenTileCatalog.sparkle
        let wilt = cropWiltLevel(p)
        PixelImage(name: p.name, width: w, height: h)
            .saturation(wilt >= 1 ? 0.35 : 1)
            .opacity(isSparkle ? (pulse ? 1 : 0.5) : (wilt >= 2 ? 0.8 : 1))
            .animation(isSparkle && !reduceMotion
                       ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : nil, value: pulse)
            .position(x: CGFloat(p.col) * cell + w / 2, y: CGFloat(p.row) * cell + h / 2)
    }

    /// Wilt level for a crop tile (by matching its cell to a plot slot); 0 for non-crop tiles.
    private func cropWiltLevel(_ p: GardenTilePlacement) -> Int {
        guard p.name.hasPrefix("crop_"),
              let i = GardenSceneModel.plotCells.firstIndex(where: { $0.col == p.col && $0.row == p.row }),
              i < snapshot.slots.count else { return 0 }
        return snapshot.slots[i].wiltLevel
    }

    // MARK: companion

    private var companionButton: some View {
        let c = GardenSceneModel.companionCell
        return Button(action: onCompanion) {
            PixelImage(name: GardenTileCatalog.companion(snapshot.companionMood), width: cell, height: cell)
                .offset(y: bob && !reduceMotion ? -2 : 0)
        }
        .buttonStyle(.plain)
        .frame(width: cell, height: cell)
        .position(x: CGFloat(c.col) * cell + cell / 2, y: CGFloat(c.row) * cell + cell / 2)
        .help("Open garden shop")
        .accessibilityLabel("Garden companion, \(moodWord). Opens the garden shop")
    }

    // MARK: plots

    private func plotButton(_ i: Int, at c: GardenCell) -> some View {
        let slot = snapshot.slots[i]
        let actionable = mode == .manual && (slot.isMature || slot.isEmpty)
        return Button {
            handleTap(i, slot)
        } label: {
            ZStack {
                Color.clear
                if actionable {
                    PixelImage(name: GardenTileCatalog.highlight, width: cell, height: cell)
                        .opacity(pulse ? 0.95 : 0.6)
                        .animation(reduceMotion ? nil
                                   : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }
            }
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: CGFloat(c.col) * cell + cell / 2, y: CGFloat(c.row) * cell + cell / 2)
        .help(plotHelp(slot))
        .accessibilityLabel(plotLabel(i, slot))
        .accessibilityHint(plotHint(slot))
        .popover(isPresented: infoBinding(i)) { plotInfo(i, slot) }
    }

    private func handleTap(_ i: Int, _ slot: GardenPlotSlot) {
        if mode == .manual && slot.isMature { onHarvest(i) }
        else if mode == .manual && slot.isEmpty { onPlant(i) }
        else { infoSlot = i }
    }

    private func plotInfo(_ i: Int, _ slot: GardenPlotSlot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plot \(i + 1)").font(.headline)
            if slot.isEmpty {
                Text("Empty. Completed focus sessions plant here automatically.")
            } else if slot.isMature {
                Text("\(GardenCatalog.displayName(for: slot.cropID ?? "")) — ready to harvest.")
            } else {
                Text("\(GardenCatalog.displayName(for: slot.cropID ?? "")) growing — stage \(slot.stage) of \(GardenCatalog.maxStage)."
                     + (slot.wiltLevel > 0 ? " A little wilted; focus today to revive it." : ""))
            }
            if mode == .automatic {
                Text("Switch to Manual mode in Settings to harvest and plant yourself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    // MARK: animation + labels

    private func startAnimations() {
        pulse = true
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { bob = true }
    }

    private var readyCount: Int { snapshot.slots.filter(\.isMature).count }

    private var moodWord: String {
        switch snapshot.companionMood {
        case .happy: return "happy"
        case .wilted: return "sleepy"
        case .idle: return "resting"
        }
    }

    private func infoBinding(_ i: Int) -> Binding<Bool> {
        Binding(get: { infoSlot == i }, set: { if !$0 { infoSlot = nil } })
    }

    private func plotLabel(_ i: Int, _ slot: GardenPlotSlot) -> String {
        if slot.isEmpty { return "Plot \(i + 1), empty" }
        let name = GardenCatalog.displayName(for: slot.cropID ?? "crop")
        if slot.isMature { return "Plot \(i + 1), \(name) ready to harvest" }
        return "Plot \(i + 1), \(name) growing, stage \(slot.stage)\(slot.wiltLevel > 0 ? ", wilted" : "")"
    }

    private func plotHint(_ slot: GardenPlotSlot) -> String {
        guard mode == .manual else { return "Shows plot details" }
        if slot.isMature { return "Harvest" }
        if slot.isEmpty { return "Plant" }
        return "Shows plot details"
    }

    private func plotHelp(_ slot: GardenPlotSlot) -> String {
        guard mode == .manual else { return "Plot details" }
        if slot.isMature { return "Harvest" }
        if slot.isEmpty { return "Plant" }
        return "Growing"
    }
}
