import SwiftUI
import DayBarCore

/// Nearest-neighbor pixel sprites for the Focus Garden strip (32×32 crop/companion tiles).
enum GardenRenderer {
    /// Display scale for 32px source art (integer → crisp pixels).
    static let pixelScale: CGFloat = 2

    struct PixelImage: View {
        let name: String
        var width: CGFloat
        var height: CGFloat

        var body: some View {
            Image(name)
                .interpolation(.none)
                .resizable()
                .frame(width: width, height: height)
                .accessibilityHidden(true)
        }
    }

    static func skyName(for season: GardenSeason) -> String {
        "garden_sky_\(season.rawValue)"
    }

    static func soilName(for season: GardenSeason) -> String {
        season == .winter ? "garden_soil_winter" : "garden_soil"
    }

    static func cropName(cropID: String?, stage: Int) -> String? {
        guard let cropID, stage >= 1 else { return nil }
        let clamped = min(4, max(1, stage))
        return "crop_\(cropID)_\(clamped)"
    }

    struct PlotView: View {
        let slot: GardenPlotSlot
        let season: GardenSeason
        var reduceMotion: Bool = false

        private var soilW: CGFloat { 32 * pixelScale }
        private var soilH: CGFloat { 20 * pixelScale }
        private var cropW: CGFloat { 32 * pixelScale }
        private var cropH: CGFloat { 32 * pixelScale }

        var body: some View {
            ZStack(alignment: .bottom) {
                PixelImage(name: GardenRenderer.soilName(for: season), width: soilW, height: soilH)
                if let crop = GardenRenderer.cropName(cropID: slot.cropID, stage: slot.stage) {
                    ZStack {
                        PixelImage(name: crop, width: cropW, height: cropH)
                        if slot.wiltLevel >= 1 {
                            PixelImage(name: "crop_wilt_overlay", width: cropW, height: cropH)
                                .opacity(slot.wiltLevel >= 2 ? 0.85 : 0.45)
                        }
                    }
                    .offset(y: -10)
                    .opacity(slot.wiltLevel >= 2 ? 0.75 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: slot.stage)
                }
            }
            .frame(width: soilW, height: cropH)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }

        private var label: String {
            if slot.isEmpty { return "Empty plot \(slot.index + 1)" }
            let name = GardenCatalog.displayName(for: slot.cropID ?? "crop")
            let wilt = slot.wiltLevel > 0 ? ", wilted" : ""
            return "\(name) stage \(slot.stage)\(wilt)"
        }
    }

    struct CompanionView: View {
        let mood: CompanionMood
        let hasScarf: Bool
        var reduceMotion: Bool = false
        @State private var bob = false

        private var size: CGFloat { 32 * pixelScale }

        var body: some View {
            ZStack {
                PixelImage(name: "companion_\(mood.rawValue)", width: size, height: size)
                if hasScarf {
                    PixelImage(name: "companion_scarf", width: size, height: size)
                }
            }
            .offset(y: bob && !reduceMotion ? -2 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    bob = true
                }
            }
            .accessibilityLabel(moodLabel)
        }

        private var moodLabel: String {
            switch mood {
            case .happy: return "Garden companion, happy"
            case .wilted: return "Garden companion, a bit wilted"
            case .idle: return "Garden companion, idle"
            }
        }
    }

    struct FenceView: View {
        private var w: CGFloat { 12 * pixelScale }
        private var h: CGFloat { 32 * pixelScale }

        var body: some View {
            PixelImage(name: "garden_fence", width: w, height: h)
        }
    }
}
