import SwiftUI
import DayBarCore

/// Compact garden summary. In the Today tab it's a button that opens the Garden tab; in Analytics
/// it's a read-only row (a modal sheet can't switch the panel tab beneath it).
struct GardenCompactSummary: View {
    let snapshot: GardenSnapshot
    var readOnly: Bool = false
    var onOpen: (() -> Void)?

    private var readyCount: Int { snapshot.slots.filter(\.isMature).count }

    var body: some View {
        if readOnly {
            content
        } else {
            Button { onOpen?() } label: { content }
                .buttonStyle(.plain)
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            PixelImage(name: GardenTileCatalog.companion(snapshot.companionMood), width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Focus Garden").font(.caption.weight(.semibold))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !readOnly {
                Text("Open Garden").font(.caption2.weight(.medium)).foregroundStyle(.orange)
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(readOnly ? [] : .isButton)
    }

    private var subtitle: String {
        var parts = ["\(snapshot.coins) coins"]
        if readyCount > 0 { parts.append("\(readyCount) ready to harvest") }
        return parts.joined(separator: " · ")
    }

    private var a11yLabel: String {
        "Focus Garden, \(snapshot.coins) coins, \(readyCount) crops ready" + (readOnly ? "" : ". Opens the Garden window")
    }
}
