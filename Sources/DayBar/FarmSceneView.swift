import SwiftUI
import SpriteKit
import DayBarCore

/// Embeds the SpriteKit `FarmScene` in SwiftUI. Rebuilds the scene's state whenever `gardenSnapshot`
/// changes (SwiftUI calls `updateNSView`); the scene guards internally so unchanged snapshots are cheap.
struct FarmSceneView: NSViewRepresentable {
    let snapshot: GardenSnapshot
    let mode: GardenActionMode
    let reduceMotion: Bool
    var onIntent: (FarmIntent) -> Void

    func makeNSView(context: Context) -> SKView {
        let view = FarmSKView()
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        let scene = FarmScene(size: CGSize(width: 720, height: 480))
        scene.scaleMode = .resizeFill
        scene.configure(snapshot: snapshot, mode: mode, reduceMotion: reduceMotion, onIntent: onIntent)
        view.presentScene(scene)
        context.coordinator.scene = scene
        return view
    }

    func updateNSView(_ view: SKView, context: Context) {
        context.coordinator.scene?.apply(snapshot: snapshot, mode: mode,
                                         reduceMotion: reduceMotion, onIntent: onIntent)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var scene: FarmScene? }
}
