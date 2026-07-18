import SwiftUI

/// A nearest-neighbor pixel sprite from the asset catalog — crisp integer scaling, no smoothing.
/// Shared by the garden canvas, HUD and shop. Decorative by default (hidden from VoiceOver);
/// wrap it in an accessible control when it needs a label.
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
