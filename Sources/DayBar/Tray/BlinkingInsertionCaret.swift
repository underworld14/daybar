import SwiftUI

/// Visible typing caret for empty focused fields. AppKit often suppresses the real
/// insertion point inside borderless nonactivating panels.
struct BlinkingInsertionCaret: View {
    @State private var visible = true

    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
