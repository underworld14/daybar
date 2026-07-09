import SwiftUI
import Charts
import DayBarCore

/// Resolves a hover location (in the overlay's local coordinate space) to the nearest known
/// data date, or `nil` when the cursor has left the plot area entirely. This is UI-layer
/// glue over Swift Charts; the actual nearest-date comparison lives in `DayBarCore`'s
/// dependency-free `ChartHoverMath.nearestDate`, which is what's unit-tested.
private func resolveHoveredDate(
    at location: CGPoint,
    proxy: ChartProxy,
    plotFrame: CGRect,
    candidates: [Date]
) -> Date? {
    guard plotFrame.contains(location) else { return nil }
    let xInPlot = location.x - plotFrame.origin.x
    guard let target: Date = proxy.value(atX: xInPlot) else { return nil }
    return ChartHoverMath.nearestDate(to: target, in: candidates)
}

/// Clamps a tooltip's center-x so its edges stay inside `plotFrame` (assumes ~80pt width).
private func clampedTooltipCenterX(_ centerX: CGFloat, in plotFrame: CGRect, estimatedHalfWidth: CGFloat = 40) -> CGFloat {
    ChartHoverMath.clampedTooltipCenterX(centerX, in: plotFrame, estimatedHalfWidth: estimatedHalfWidth)
}

/// Wraps a chart with hover tracking: the wrapped `chart` closure receives the currently
/// hovered date (or `nil`) so it can draw its own crosshair `RuleMark`. Tooltips are drawn
/// in the chart overlay so they don't participate in chart layout (in-chart annotations
/// were expanding the plot and clipping inside the fixed-height chart sections).
struct HoverableChart<ChartContent: View>: View {
    let dates: [Date]
    var tooltip: ((Date) -> [String])?
    @ViewBuilder var chart: (Date?) -> ChartContent

    @State private var hoveredDate: Date?
    @State private var hoverLocation: CGPoint?

    var body: some View {
        chart(hoveredDate)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plotFrame = geometry[proxy.plotAreaFrame]
                    ZStack {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hoverLocation = location
                                    hoveredDate = resolveHoveredDate(
                                        at: location, proxy: proxy, plotFrame: plotFrame, candidates: dates
                                    )
                                case .ended:
                                    hoveredDate = nil
                                    hoverLocation = nil
                                }
                            }

                        if let hoveredDate, let hoverLocation, let lines = tooltip?(hoveredDate) {
                            ChartHoverTooltip(lines: lines)
                                .fixedSize()
                                .position(
                                    x: clampedTooltipCenterX(hoverLocation.x, in: plotFrame),
                                    y: plotFrame.origin.y + 18
                                )
                        }
                    }
                }
            }
            .onChange(of: dates) { _, _ in
                hoveredDate = nil
                hoverLocation = nil
            }
    }
}

/// Small floating label used by every chart's hover tooltip.
struct ChartHoverTooltip: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(lines, id: \.self) { line in
                Text(line).font(.caption2.weight(.medium))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
