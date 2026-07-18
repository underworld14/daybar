import SwiftUI
import DayBarCore

/// Procedural pixel-cozy drawing for garden plots and companion.
enum GardenRenderer {
    static func seasonSky(_ season: GardenSeason) -> Color {
        switch season {
        case .spring: return Color(red: 0.72, green: 0.88, blue: 0.95)
        case .summer: return Color(red: 0.55, green: 0.78, blue: 0.95)
        case .autumn: return Color(red: 0.90, green: 0.78, blue: 0.58)
        case .winter: return Color(red: 0.78, green: 0.84, blue: 0.92)
        }
    }

    static func seasonSoil(_ season: GardenSeason) -> Color {
        switch season {
        case .spring: return Color(red: 0.45, green: 0.32, blue: 0.20)
        case .summer: return Color(red: 0.42, green: 0.28, blue: 0.16)
        case .autumn: return Color(red: 0.40, green: 0.26, blue: 0.14)
        case .winter: return Color(red: 0.50, green: 0.48, blue: 0.46)
        }
    }

    static func cropColor(cropID: String?, stage: Int) -> Color {
        guard stage > 0, let cropID else { return .clear }
        let base: Color = {
            switch cropID {
            case "cauliflower": return Color(red: 0.85, green: 0.88, blue: 0.70)
            case "berry": return Color(red: 0.75, green: 0.25, blue: 0.40)
            default: return Color(red: 0.85, green: 0.72, blue: 0.35)
            }
        }()
        let opacity = 0.35 + 0.15 * Double(min(stage, 4))
        return base.opacity(opacity)
    }

    struct PlotView: View {
        let slot: GardenPlotSlot
        let season: GardenSeason
        var reduceMotion: Bool = false

        var body: some View {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(GardenRenderer.seasonSoil(season))
                    .frame(width: 28, height: 18)
                if !slot.isEmpty {
                    cropShape
                        .frame(width: cropSize, height: cropSize)
                        .offset(y: -6)
                        .opacity(slot.wiltLevel >= 2 ? 0.45 : slot.wiltLevel == 1 ? 0.7 : 1)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: slot.stage)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }

        @ViewBuilder
        private var cropShape: some View {
            let color = GardenRenderer.cropColor(cropID: slot.cropID, stage: slot.stage)
            switch slot.stage {
            case 1:
                Circle().fill(color).frame(width: 6, height: 6)
            case 2:
                Capsule().fill(Color.green.opacity(0.7)).frame(width: 4, height: 10)
            case 3:
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 12)
            default:
                Image(systemName: slot.cropID == "berry" ? "circle.fill" : "leaf.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(color)
            }
        }

        private var cropSize: CGFloat {
            CGFloat(8 + min(slot.stage, 4) * 3)
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
        let season: GardenSeason
        var reduceMotion: Bool = false
        @State private var bob = false

        var body: some View {
            ZStack {
                Circle()
                    .fill(bodyColor)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .offset(x: -4, y: -2)
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .offset(x: 4, y: -2)
                if hasScarf {
                    Capsule()
                        .fill(scarfColor)
                        .frame(width: 16, height: 4)
                        .offset(y: 6)
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

        private var bodyColor: Color {
            switch mood {
            case .happy: return Color(red: 0.95, green: 0.75, blue: 0.35)
            case .wilted: return Color(red: 0.65, green: 0.62, blue: 0.55)
            case .idle: return Color(red: 0.85, green: 0.70, blue: 0.45)
            }
        }

        private var scarfColor: Color {
            switch season {
            case .spring: return Color(red: 0.40, green: 0.70, blue: 0.55)
            case .summer: return Color(red: 0.95, green: 0.55, blue: 0.30)
            case .autumn: return Color(red: 0.85, green: 0.40, blue: 0.25)
            case .winter: return Color(red: 0.45, green: 0.55, blue: 0.85)
            }
        }

        private var moodLabel: String {
            switch mood {
            case .happy: return "Garden companion, happy"
            case .wilted: return "Garden companion, a bit wilted"
            case .idle: return "Garden companion, idle"
            }
        }
    }
}
