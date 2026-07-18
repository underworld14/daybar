import SpriteKit
import DayBarCore

/// An action the farm scene asks the app to perform. The scene never mutates state itself.
enum FarmIntent: Equatable {
    case harvest(Int)
    case plant(Int)
    case collectAnimal(UUID)
    case plotInfo(Int)
    case openShop
}

/// SKView subclass that can become first responder (mouse works today; keyboard roaming is a
/// future phase that will forward `keyDown` — the hook is here so it's a drop-in later).
final class FarmSKView: SKView {
    override var acceptsFirstResponder: Bool { true }
}

/// The roaming farm: renders `FarmWorldModel` at an integer point-per-tile, walks a cozy farmer to
/// clicked cells via A*, and reports interactions through `onIntent`. A thin renderer — all rules
/// live in the pure `FarmWorldModel`.
final class FarmScene: SKScene {
    private let ppt: CGFloat = 48
    private var rows: Int { FarmWorldModel.rows }
    private var cols: Int { FarmWorldModel.cols }
    private var worldW: CGFloat { CGFloat(cols) * ppt }
    private var worldH: CGFloat { CGFloat(rows) * ppt }

    private var snapshot: GardenSnapshot?
    private var mode: GardenActionMode = .automatic
    private var reduceMotion = false
    var onIntent: ((FarmIntent) -> Void)?

    private let cameraNode = SKCameraNode()
    private let farmer = SKSpriteNode()
    private var placementNodes: [SKNode] = []
    private var textureCache: [String: SKTexture] = [:]
    private var built = false

    // Movement
    private var pathQueue: [GardenCell] = []
    private var pending: FarmInteractionTarget = .none
    private var facing = "down"
    private var walking = false
    private var lastUpdate: TimeInterval = 0
    private let speedTilesPerSec: CGFloat = 3.0

    // MARK: - Setup

    func configure(snapshot: GardenSnapshot, mode: GardenActionMode, reduceMotion: Bool,
                   onIntent: @escaping (FarmIntent) -> Void) {
        self.snapshot = snapshot
        self.mode = mode
        self.reduceMotion = reduceMotion
        self.onIntent = onIntent
    }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = SKColor(red: 0.42, green: 0.64, blue: 0.32, alpha: 1) // grass-ish, seen only past edges
        anchorPoint = CGPoint(x: 0, y: 0)
        addChild(cameraNode)
        camera = cameraNode

        farmer.size = CGSize(width: ppt, height: ppt)
        farmer.texture = texture(FarmTileCatalog.character(idle: facing))
        farmer.position = pointOfCell(GardenCell(6, 8))   // spawn on the path spine
        addChild(farmer)

        rebuildScene()
        updateCamera()
    }

    /// Push fresh state into the scene. Cheap when unchanged (Equatable guard by the caller); rebuilds
    /// the placement nodes when the snapshot or mode changes.
    func apply(snapshot: GardenSnapshot, mode: GardenActionMode, reduceMotion: Bool,
               onIntent: @escaping (FarmIntent) -> Void) {
        self.onIntent = onIntent
        let changed = snapshot != self.snapshot || mode != self.mode || reduceMotion != self.reduceMotion
        self.snapshot = snapshot
        self.mode = mode
        self.reduceMotion = reduceMotion
        if built && changed { rebuildScene() }
    }

    // MARK: - Rendering

    private func texture(_ name: String) -> SKTexture {
        if let t = textureCache[name] { return t }
        let t = SKTexture(imageNamed: name)
        t.filteringMode = .nearest
        textureCache[name] = t
        return t
    }

    private func rebuildScene() {
        placementNodes.forEach { $0.removeFromParent() }
        placementNodes.removeAll()
        guard let snap = snapshot else { return }
        for p in FarmWorldModel.placements(for: snap) {
            let node = SKSpriteNode(texture: texture(p.name))
            node.size = CGSize(width: CGFloat(p.wTiles) * ppt, height: CGFloat(p.hTiles) * ppt)
            node.position = pointOfPlacement(p)
            node.zPosition = zPosition(for: p)
            if p.name == GardenTileCatalog.sparkle && !reduceMotion {
                node.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.5, duration: 0.9), .fadeAlpha(to: 1.0, duration: 0.9)])))
            }
            addChild(node)
            placementNodes.append(node)
        }
        updateFarmerZ()
    }

    private func zPosition(for p: GardenTilePlacement) -> CGFloat {
        if isGround(p.name) { return CGFloat(p.row) * 0.1 }
        if isFX(p.name) { return 5000 + CGFloat(p.row) * 0.1 }
        return 1000 + CGFloat(p.row + p.hTiles)   // actor band: lower on screen = in front
    }

    private func isGround(_ name: String) -> Bool {
        name.hasPrefix("tile_grass") || name == GardenTileCatalog.path
            || name.hasPrefix("water_") || name.hasPrefix("plot_soil_")
            || name == FarmTileCatalog.bridgeH || name == FarmTileCatalog.bridgeV
    }

    private func isFX(_ name: String) -> Bool {
        name == GardenTileCatalog.sparkle || name == GardenTileCatalog.rain || name == GardenTileCatalog.highlight
    }

    // MARK: - Coordinates

    private func pointOfCell(_ c: GardenCell) -> CGPoint {
        CGPoint(x: (CGFloat(c.col) + 0.5) * ppt, y: (CGFloat(rows) - CGFloat(c.row) - 0.5) * ppt)
    }

    private func pointOfPlacement(_ p: GardenTilePlacement) -> CGPoint {
        CGPoint(x: (CGFloat(p.col) + CGFloat(p.wTiles) / 2) * ppt,
                y: (CGFloat(rows) - CGFloat(p.row) - CGFloat(p.hTiles) / 2) * ppt)
    }

    private func cellOfPoint(_ p: CGPoint) -> GardenCell {
        GardenCell(Int(floor(p.x / ppt)), rows - 1 - Int(floor(p.y / ppt)))
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        guard let snap = snapshot, let view = view else { return }
        let scenePoint = convertPoint(fromView: view.convert(event.locationInWindow, from: nil))
        let cell = cellOfPoint(scenePoint)

        if cell == FarmWorldModel.companionCell { onIntent?(.openShop); return }

        let target = FarmWorldModel.interactionTarget(at: cell, animals: snap.animals)
        switch target {
        case .none:
            if FarmWorldModel.isWalkable(cell, animals: snap.animals) { walk(to: cell, then: .none) }
        default:
            guard let targetCell = resolveCell(for: target, in: snap) else { return }
            let from = cellOfPoint(farmer.position)
            if let dest = FarmWorldModel.adjacentWalkableCell(to: targetCell, from: from, animals: snap.animals) {
                walk(to: dest, then: target)
            }
        }
    }

    private func resolveCell(for target: FarmInteractionTarget, in snap: GardenSnapshot) -> GardenCell? {
        switch target {
        case .plot(let i): return FarmWorldModel.plotCells.indices.contains(i) ? FarmWorldModel.plotCells[i] : nil
        case .sign: return FarmWorldModel.signCell
        case .animal(let id):
            guard let a = snap.animals.first(where: { $0.id == id }), let idx = a.cell,
                  FarmWorldModel.penCells.indices.contains(idx) else { return nil }
            return FarmWorldModel.penCells[idx]
        case .none: return nil
        }
    }

    private func walk(to dest: GardenCell, then target: FarmInteractionTarget) {
        guard let snap = snapshot else { return }
        let from = cellOfPoint(farmer.position)
        guard let path = FarmPathfinding.path(from: from, to: dest,
                                              isWalkable: { FarmWorldModel.isWalkable($0, animals: snap.animals) })
        else { return }
        pathQueue = Array(path.dropFirst())   // current cell excluded
        pending = target
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        if lastUpdate == 0 { lastUpdate = currentTime }
        let dt = CGFloat(min(currentTime - lastUpdate, 1.0 / 30))
        lastUpdate = currentTime
        stepFarmer(dt: dt)
        updateCamera()
        updateFarmerZ()
    }

    private func stepFarmer(dt: CGFloat) {
        guard let next = pathQueue.first else {
            if walking { setWalking(false) }
            firePendingIfAny()
            return
        }
        let target = pointOfCell(next)
        let dx = target.x - farmer.position.x, dy = target.y - farmer.position.y
        let dist = hypot(dx, dy)
        let step = speedTilesPerSec * ppt * dt
        if dist <= step || dist == 0 {
            farmer.position = target
            pathQueue.removeFirst()
        } else {
            farmer.position = CGPoint(x: farmer.position.x + dx / dist * step,
                                      y: farmer.position.y + dy / dist * step)
            updateFacing(dx: dx, dy: dy)
            setWalking(true)
        }
    }

    private func firePendingIfAny() {
        guard pending != .none, let snap = snapshot else { pending = .none; return }
        // Face the target before acting.
        if let tc = resolveCell(for: pending, in: snap) {
            let fc = cellOfPoint(farmer.position)
            updateFacing(dx: CGFloat(tc.col - fc.col), dy: CGFloat(fc.row - tc.row))
            setWalking(false)
        }
        switch pending {
        case .plot(let i):
            guard snap.slots.indices.contains(i) else { break }
            let slot = snap.slots[i]
            if mode == .manual && slot.isMature { onIntent?(.harvest(i)) }
            else if mode == .manual && slot.isEmpty { onIntent?(.plant(i)) }
            else { onIntent?(.plotInfo(i)) }
        case .animal(let id):
            if let a = snap.animals.first(where: { $0.id == id }), a.hasProduct { onIntent?(.collectAnimal(id)) }
        case .sign:
            onIntent?(.openShop)
        case .none:
            break
        }
        pending = .none
    }

    private func updateFacing(dx: CGFloat, dy: CGFloat) {
        let newFacing: String
        if abs(dx) >= abs(dy) { newFacing = dx >= 0 ? "right" : "left" }
        else { newFacing = dy >= 0 ? "up" : "down" }   // scene y-up: +dy = up (north)
        if newFacing != facing {
            facing = newFacing
            if walking { setWalking(true) } else { farmer.texture = texture(FarmTileCatalog.character(idle: facing)) }
        }
    }

    private func setWalking(_ on: Bool) {
        if on {
            walking = true
            farmer.removeAction(forKey: "walk")
            let frames = FarmTileCatalog.walkFrames.map { texture(FarmTileCatalog.character(walk: facing, frame: $0)) }
            farmer.run(.repeatForever(.animate(with: frames, timePerFrame: 0.12, resize: false, restore: false)),
                       withKey: "walk")
        } else {
            walking = false
            farmer.removeAction(forKey: "walk")
            farmer.texture = texture(FarmTileCatalog.character(idle: facing))
        }
    }

    private func updateFarmerZ() {
        // Continuous y-sort: lower on screen (smaller y) = more in front.
        let footY = farmer.position.y - ppt / 2
        farmer.zPosition = 1000 + (worldH - footY) / ppt
    }

    private func updateCamera() {
        let halfW = size.width / 2, halfH = size.height / 2
        var x = farmer.position.x, y = farmer.position.y
        x = worldW <= size.width ? worldW / 2 : min(max(x, halfW), worldW - halfW)
        y = worldH <= size.height ? worldH / 2 : min(max(y, halfH), worldH - halfH)
        cameraNode.position = CGPoint(x: x.rounded(), y: y.rounded())
    }
}
