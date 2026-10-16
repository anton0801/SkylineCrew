import SpriteKit
import UIKit

/// Renders the run model with the production sprites. It never decides an outcome:
/// SpriteKit contacts are not used; positions are derived from the reducer state every frame.
///
/// Geometry follows design/screens/09_building.svg (390×844 pt):
/// floors 174×54 with a 48 pt step (lowest top at y=594), plaza P02 (73,636,244×54),
/// crane P01 (214,196,183×79), pulley (248,217), hanging floor 174×62 at y=264,
/// target guide 174×20 at top−10, brace band 176×20 at top+43.
final class GameScene: SKScene {
    weak var controller: GameController?
    var reduceMotion = false
    var metrics = MockMetrics.reference {
        didSet { if metrics != oldValue { relayout() } }
    }

    // Design constants
    private let k: CGFloat = 174.0 / 180.0
    private let floorW: CGFloat = 174
    private let floorH: CGFloat = 54
    private let hangH: CGFloat = 62
    private let step: CGFloat = 48
    private let firstTop: CGFloat = 594
    private let topLimit: CGFloat = 354
    private let pulley = CGPoint(x: 248, y: 217)

    private let world = SKNode()
    private let nudge = SKNode()
    private let tower = SKNode()
    private let plaza = SKSpriteNode()
    private var floorNodes: [SKSpriteNode] = []
    private let guide = SKSpriteNode()
    private let brace = SKSpriteNode()
    private let crane = SKSpriteNode()
    private let rope = SKShapeNode()
    private let hanging = SKSpriteNode()
    private let falling = SKSpriteNode()
    private let roof = SKSpriteNode()
    private let beacon = SKShapeNode(circleOfRadius: 9)
    private let label = SKLabelNode(fontNamed: Typo.faceName)
    private let star = SKSpriteNode()
    private let outline = SKShapeNode()

    private var camX: Double = 0
    private var shift: CGFloat = 0
    private var hangTop: CGFloat = 264
    private var lastTime: TimeInterval?
    private var lastHangingX: Double = 0
    private var releaseX: Double?
    private var ropeHookX: CGFloat = 254
    private var configured = false
    private var primed = false

    override init() {
        super.init(size: DesignRef.reference)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Setup

    private func configure() {
        guard !configured else { return }
        configured = true
        addChild(world)
        world.addChild(nudge)
        nudge.addChild(tower)

        let cache = ArtCache.shared
        plaza.texture = cache.texture("P02")
        let plazaAspect = ArtManifest.aspect("P02")
        plaza.size = CGSize(width: min(244, 54 * plazaAspect), height: min(54, 244 / plazaAspect))
        plaza.position = local(195, 663)
        plaza.zPosition = 5
        tower.addChild(plaza)

        guide.texture = cache.uiTexture("target_guide")
        guide.size = CGSize(width: floorW, height: 20)
        guide.zPosition = 300
        tower.addChild(guide)

        brace.texture = cache.uiTexture("brace_band")
        brace.size = CGSize(width: 176, height: 20)
        brace.zPosition = 301
        tower.addChild(brace)

        roof.texture = cache.texture("P03")
        roof.size = CGSize(width: floorW, height: 57)
        roof.zPosition = 280
        roof.isHidden = true
        tower.addChild(roof)

        beacon.fillColor = UIColor(hex: 0xFFE872, alpha: 0.95)
        beacon.strokeColor = UIColor(hex: 0xFFD437, alpha: 0.6)
        beacon.glowWidth = 10
        beacon.lineWidth = 2
        beacon.zPosition = 281
        beacon.isHidden = true
        tower.addChild(beacon)

        label.fontSize = 30
        label.fontColor = UIColor(hex: 0x103677)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .baseline
        label.zPosition = 400
        label.alpha = 0
        tower.addChild(label)

        star.texture = cache.texture("R02")
        let starAspect = ArtManifest.aspect("R02")
        star.size = CGSize(width: 45 * min(1, starAspect), height: 45 / max(1, starAspect))
        star.zPosition = 401
        star.alpha = 0
        tower.addChild(star)

        outline.path = CGPath(roundedRect: CGRect(x: -89, y: -29, width: 178, height: 58), cornerWidth: 6, cornerHeight: 6, transform: nil)
        outline.strokeColor = UIColor(hex: 0xEFFFFF)
        outline.lineWidth = 3
        outline.glowWidth = 4
        outline.fillColor = .clear
        outline.zPosition = 302
        outline.alpha = 0
        tower.addChild(outline)

        crane.texture = cache.texture("P01")
        let craneAspect = ArtManifest.aspect("P01")
        let craneSize = craneAspect > 183.0 / 79.0 ? CGSize(width: 183, height: 183 / craneAspect) : CGSize(width: 79 * craneAspect, height: 79)
        crane.size = craneSize
        crane.position = local(214 + 91.5, 196 + 39.5)
        crane.zPosition = 120
        world.addChild(crane)

        rope.strokeColor = UIColor(hex: 0x455B65)
        rope.lineWidth = 2
        rope.lineCap = .round
        rope.lineJoin = .round
        rope.zPosition = 130
        world.addChild(rope)

        hanging.size = CGSize(width: floorW, height: hangH)
        hanging.zPosition = 150
        world.addChild(hanging)

        falling.size = CGSize(width: floorW, height: hangH)
        falling.zPosition = 160
        falling.isHidden = true
        world.addChild(falling)
    }

    override func didMove(to view: SKView) {
        configure()
        relayout()
        view.isMultipleTouchEnabled = false
    }

    override func didChangeSize(_ oldSize: CGSize) {
        relayout()
    }

    private func relayout() {
        guard configured, size.width > 0 else { return }
        let m = metrics
        let bandTop = 164 + m.topShift
        let bandBottom = 664 + m.bottomShift
        let avail = bandBottom - bandTop
        var s: CGFloat = avail >= 500 - 16 ? 1 : max(0.5, avail / 500)
        s = min(s, size.width / DesignRef.reference.width)
        world.setScale(s)
        world.position = CGPoint(x: size.width / 2, y: size.height - bandBottom)
    }

    /// Design point (mockup, y down) → world/tower local point (y up, origin at (195, 664)).
    private func local(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x - 195, y: 664 - y) }

    private func topY(_ n: Int) -> CGFloat { n > 0 ? firstTop - step * CGFloat(n - 1) : firstTop + step }

    /// The hook lowers toward short towers (practice starts at y=355 as in 08) and rises to y=264 (09).
    private func targetHangTop(visibleTop: CGFloat) -> CGFloat {
        if isTutorial { return 355 }
        return min(355, max(264, visibleTop - 191))
    }

    /// Practice keeps the swinging floor below the hint bubble, so its camera follows earlier.
    private var cameraTopLimit: CGFloat { isTutorial ? 470 : topLimit }
    private var isTutorial = false

    // MARK: Frame

    override func update(_ currentTime: TimeInterval) {
        let raw = lastTime.map { currentTime - $0 } ?? 0
        lastTime = currentTime
        MainActor.assumeIsolated {
            guard let c = controller else { return }
            c.tick(currentTime)
            let dt = (isPaused || !c.isRunning) ? 0 : min(raw, 1.0 / 15.0)
            render(c, dt: dt)
        }
    }

    @MainActor
    private func render(_ c: GameController, dt: Double) {
        let s = c.session
        let n = s.floorCount

        if !primed {
            primed = true
            isTutorial = c.mode == .tutorial
            // Fixtures freeze the frame exactly as drawn in the mockups (camera not yet moved).
            camX = c.frozen ? 0 : s.topX
            let settledCount = s.stage == .settling ? max(0, n - 1) : n
            shift = max(0, cameraTopLimit - topY(settledCount))
            hangTop = targetHangTop(visibleTop: topY(n) + shift)
            ropeHookX = 195 + CGFloat(c.hangingOffset()) * k
        }

        for cue in c.drainCues() { handle(cue, c) }

        if dt > 0 {
            camX += (s.topX - camX) * (1 - exp(-dt / 0.055))
            if s.stage != .dropping && s.stage != .failing {
                let targetShift = max(0, cameraTopLimit - topY(n))
                shift += (targetShift - shift) * CGFloat(1 - exp(-dt / 0.09))
                if abs(targetShift - shift) < 0.05 { shift = targetShift }
            }
            let targetHang = targetHangTop(visibleTop: topY(n) + shift)
            if s.stage == .aiming || s.stage == .settling {
                hangTop += (targetHang - hangTop) * CGFloat(1 - exp(-dt / 0.12))
            }
        }
        // Tower content uses unshifted design y; the camera moves the whole tower down/sideways.
        tower.position = CGPoint(x: -CGFloat(camX) * k, y: -shift)

        syncFloors(s)

        let topXp = CGFloat(s.topX) * k
        let top = topY(n)
        let showGuide = s.stage == .aiming || s.stage == .dropping || s.stage == .settling
        guide.isHidden = !showGuide
        guide.position = CGPoint(x: topXp, y: 664 - top)
        brace.isHidden = !(s.braceCharged || s.braceArmed) || !showGuide
        brace.position = CGPoint(x: topXp, y: 664 - (top + 53))

        // Hanging floor & rope
        let hx = s.topX + c.hangingOffset() - camX
        let hxDesign = 195 + CGFloat(hx) * k
        switch s.stage {
        case .aiming:
            lastHangingX = s.topX + c.hangingOffset()
            hanging.isHidden = false
            hanging.texture = ArtCache.shared.texture(c.engine.nextAsset(s))
            hanging.size = CGSize(width: floorW, height: hangH)
            hanging.position = CGPoint(x: CGFloat(hx) * k, y: 664 - (hangTop + hangH / 2))
            ropeHookX = hxDesign
            drawRope(hookX: hxDesign, withBridle: true)
            falling.isHidden = true
        case .dropping:
            hanging.isHidden = true
            drawRope(hookX: ropeHookX, withBridle: false)
            renderFall(s)
        case .failing:
            hanging.isHidden = true
            drawRope(hookX: ropeHookX, withBridle: false)
            renderFailing(s)
        case .settling:
            hanging.isHidden = true
            falling.isHidden = true
            drawRope(hookX: ropeHookX, withBridle: false)
        case .roofing, .won, .failed:
            hanging.isHidden = true
            falling.isHidden = true
            drawRope(hookX: ropeHookX, withBridle: false)
        }

        renderRoof(s, c)

        if c.frozen, s.stage == .settling, s.lastLanding == .perfect || s.lastLanding == .steady {
            // Static frame of 10_perfect_drop for screenshot comparison.
            label.removeAllActions(); star.removeAllActions()
            label.text = s.lastLanding == .steady ? "STEADY!" : "PERFECT!"
            label.position = CGPoint(x: CGFloat(s.topX) * k, y: 664 - (topY(s.floorCount) - 20))
            label.alpha = 1
            star.position = CGPoint(x: CGFloat(s.topX) * k + 104.5, y: 664 - (topY(s.floorCount) + 41.5))
            star.alpha = s.lastLanding == .perfect ? 1 : 0
        }
    }

    private func syncFloors(_ s: RunSession) {
        let n = s.floorCount
        while floorNodes.count < n {
            let node = SKSpriteNode()
            node.size = CGSize(width: floorW, height: floorH)
            tower.addChild(node)
            floorNodes.append(node)
        }
        while floorNodes.count > n {
            floorNodes.removeLast().removeFromParent()
        }
        for (i, p) in s.placements.enumerated() {
            let node = floorNodes[i]
            let tex = ArtCache.shared.texture(p.assetID)
            if node.texture !== tex { node.texture = tex }
            node.position = CGPoint(x: CGFloat(p.centerX) * k, y: 43 + step * CGFloat(i))
            node.zPosition = 10 + CGFloat(i) * 0.5
            // Off-screen floors are not drawn; the model keeps every placement.
            node.isHidden = (43 + step * CGFloat(i) - shift) < -320
        }
    }

    private func drawRope(hookX: CGFloat, withBridle: Bool) {
        let path = CGMutablePath()
        let hookY = hangTop - 13
        path.move(to: local(pulley.x, pulley.y))
        path.addLine(to: local(hookX, hookY))
        if withBridle {
            path.move(to: local(hookX, hookY))
            path.addLine(to: local(hookX - 72, hangTop + 5))
            path.move(to: local(hookX, hookY))
            path.addLine(to: local(hookX + 71, hangTop + 5))
        }
        rope.path = path
    }

    /// 350 ms accelerating fall from the hanging position to the top of the tower.
    private func renderFall(_ s: RunSession) {
        guard let plan = s.planned else { falling.isHidden = true; return }
        let p = CGFloat(min(1, s.stageTime / RunRules.dropDuration))
        let e = p * p
        let startUnits = releaseX ?? (s.topX + plan.dx)
        let endUnits = plan.braced ? s.topX : s.topX + plan.dx
        let startX = CGFloat(startUnits - camX) * k
        let endX = CGFloat(endUnits - camX) * k
        let n = s.floorCount
        let landingTop = firstTop - step * CGFloat(n) + shift
        let startCenter = hangTop + hangH / 2
        let endCenter = landingTop + floorH / 2
        let h = hangH + (floorH - hangH) * e
        falling.isHidden = false
        falling.alpha = 1
        falling.zRotation = 0
        falling.texture = ArtCache.shared.texture(plan.assetID)
        falling.size = CGSize(width: floorW, height: h)
        falling.position = CGPoint(x: startX + (endX - startX) * (plan.braced ? e : 1), y: 664 - (startCenter + (endCenter - startCenter) * e))
    }

    /// Soft, non-dramatic failure: a missed floor drifts down out of the scene; a strained one tips off.
    private func renderFailing(_ s: RunSession) {
        guard let plan = s.planned else { falling.isHidden = true; return }
        let q = CGFloat(min(1, s.stageTime / RunRules.failingDuration))
        let sign: CGFloat = plan.dx >= 0 ? 1 : -1
        let n = s.floorCount
        let landingTop = firstTop - step * CGFloat(n) + shift
        let x = CGFloat(s.topX + plan.dx - camX) * k
        falling.isHidden = false
        falling.texture = ArtCache.shared.texture(plan.assetID)
        falling.size = CGSize(width: floorW, height: floorH)
        if s.failReason == .tooMuchStrain {
            let tip = q < 0.35 ? 0 : (q - 0.35) / 0.65
            falling.zRotation = -sign * (0.06 * sin(q * .pi * 3) * (1 - tip) + 0.35 * tip * tip)
            falling.position = CGPoint(x: x + sign * 60 * tip * tip, y: 664 - (landingTop + floorH / 2 + 160 * tip * tip))
            falling.alpha = 1 - tip * tip
        } else {
            falling.zRotation = -sign * 0.3 * q
            falling.position = CGPoint(x: x + sign * 34 * q, y: 664 - (landingTop + floorH / 2 + 300 * q * q))
            falling.alpha = 1 - q
        }
    }

    @MainActor
    private func renderRoof(_ s: RunSession, _ c: GameController) {
        let n = s.floorCount
        let top = topY(n)
        let x = CGFloat(s.topX) * k
        let seatCenter = top - 52 + 57.0 / 2
        switch s.stage {
        case .roofing:
            roof.isHidden = false
            let reduce = reduceMotion || c.engine.context.reduceMotion
            if reduce {
                roof.alpha = CGFloat(min(1, s.stageTime / RunRules.reducedMotionRoof))
                roof.position = CGPoint(x: x, y: 664 - seatCenter)
            } else {
                let q = CGFloat(min(1, s.stageTime / RunRules.roofInstall))
                let eased = 1 - pow(1 - q, 3)
                roof.alpha = min(1, q * 3)
                roof.position = CGPoint(x: x, y: 664 - (seatCenter - 140 * (1 - eased)))
            }
            let beaconAt = c.engine.context.beaconMoment
            if s.stageTime >= beaconAt {
                beacon.isHidden = false
                let q = CGFloat(min(1, (s.stageTime - beaconAt) / max(0.1, c.engine.context.roofDuration - beaconAt)))
                beacon.alpha = 0.35 + 0.6 * q
                beacon.setScale(0.6 + 0.4 * q)
            } else {
                beacon.isHidden = true
            }
            beacon.position = CGPoint(x: x, y: 664 - (top - 52 + 8))
        case .won:
            roof.isHidden = false
            roof.alpha = 1
            roof.position = CGPoint(x: x, y: 664 - seatCenter)
            beacon.isHidden = false
            beacon.alpha = 0.95
            beacon.setScale(1)
            beacon.position = CGPoint(x: x, y: 664 - (top - 52 + 8))
        default:
            roof.isHidden = true
            beacon.isHidden = true
        }
    }

    // MARK: Cues

    @MainActor
    private func handle(_ cue: RunEvent, _ c: GameController) {
        let s = c.session
        switch cue {
        case .released:
            releaseX = lastHangingX
        case .landed(let kind, _, _):
            releaseX = nil
            let n = s.floorCount
            let top = topY(n)
            let x = CGFloat(s.topX) * k
            if kind == .perfect || kind == .steady {
                showFlash(kind == .perfect ? "PERFECT!" : "STEADY!", star: kind == .perfect, x: x, top: top)
            }
            outline.removeAllActions()
            outline.alpha = 0
            if kind != .normal {
                // Perfect outline 450 ms / brace glow around the landed floor.
                outline.position = CGPoint(x: x, y: 664 - (top + floorH / 2))
                outline.alpha = 1
                outline.run(.fadeOut(withDuration: kind == .steady ? 0.6 : 0.45))
            }
            if !reduceMotion {
                nudge.removeAllActions()
                nudge.position = .zero
                nudge.run(.sequence([.moveBy(x: 0, y: -4, duration: 0.05), .moveBy(x: 0, y: 4, duration: 0.05)]))
            }
        case .braceArmed:
            brace.removeAllActions()
            brace.setScale(1)
            if !reduceMotion {
                brace.run(.sequence([.group([.scale(to: 1.08, duration: 0.15), .fadeAlpha(to: 0.7, duration: 0.15)]),
                                     .group([.scale(to: 1.0, duration: 0.45), .fadeAlpha(to: 1, duration: 0.45)])]))
            }
        case .aimingStarted:
            hanging.removeAllActions()
            if reduceMotion { hanging.alpha = 1 } else {
                hanging.alpha = 0
                hanging.run(.fadeIn(withDuration: 0.12))
            }
        case .missed, .tooMuchStrain:
            label.removeAllActions(); label.alpha = 0
            star.removeAllActions(); star.alpha = 0
        default:
            break
        }
    }

    /// “Perfect!” for 450 ms above the new top edge (never over the next landing line).
    private func showFlash(_ text: String, star withStar: Bool, x: CGFloat, top: CGFloat) {
        label.text = text
        label.position = CGPoint(x: x, y: 664 - (top - 20))
        label.removeAllActions()
        label.alpha = 0
        label.run(.sequence([.fadeIn(withDuration: 0.06), .wait(forDuration: 0.33), .fadeOut(withDuration: 0.06)]))
        star.removeAllActions()
        star.alpha = 0
        if withStar {
            star.position = CGPoint(x: x + 104.5, y: 664 - (top + 41.5))
            star.run(.sequence([.fadeIn(withDuration: 0.06), .wait(forDuration: 0.33), .fadeOut(withDuration: 0.06)]))
        }
    }

}
