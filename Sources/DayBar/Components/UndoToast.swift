import SwiftUI
import DayBarCore

/// Renders `AppState.ephemeralBanner` (milestones, acknowledgments, Undo) and dismisses it
/// after 3 s (5 s when it carries an undo).
struct UndoToast: View {
    enum Style {
        /// A quiet line inside the tray.
        case inline
        /// A floating capsule over the window content.
        case floating
    }

    var appState: AppState
    var style: Style = .inline

    var body: some View {
        if let banner = appState.ephemeralBanner {
            content(banner)
                .task(id: banner.id) {
                    try? await Task.sleep(for: .seconds(banner.undoToken == nil ? 3 : 5))
                    if appState.ephemeralBanner?.id == banner.id {
                        appState.dismissBanner()
                    }
                }
        }
    }

    @ViewBuilder
    private func content(_ banner: EphemeralBanner) -> some View {
        let row = HStack(spacing: ThemeMetrics.spacingM) {
            Text(banner.message)
                .font(.caption)
                .foregroundStyle(style == .inline ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            if let label = banner.undoLabel, let token = banner.undoToken {
                Button(label) { appState.performUndo(token: token) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(label)
            }
            if style == .inline { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .combine)

        switch style {
        case .inline:
            row.padding(.vertical, 2)
        case .floating:
            row
                .padding(.horizontal, ThemeMetrics.spacingL)
                .padding(.vertical, ThemeMetrics.spacingS + 1)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }
}
