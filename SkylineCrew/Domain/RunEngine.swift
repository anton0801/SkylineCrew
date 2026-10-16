import Foundation

// MARK: - Constants of the run rules (docs/01 “Gameplay: модель и состояния”)

enum RunRules {
    static let dropDuration = 0.35
    static let settlePerfect = 0.45
    static let settleNormal = 0.30
    static let failingDuration = 0.70
    static let roofInstall = 0.9
    static let beaconOn = 0.4
    static let reducedMotionRoof = 0.2
    static let missRatio = 0.42
    static let strainFactor = 110.0
    static let perfectRelief = 10
    static let braceRelief = 20
    static let strainWarning = 60
    static let strainCritical = 85
    static let timingAssistFactor = 0.65
    static let tutorialSlowFactor = 0.6
    static let tutorialSteps = 4
    static let tutorialPresetFloors = 2
    static let freeBuildPhaseSeed = 7919
    /// Tolerance against binary floating point noise on exact boundaries (.045, .42).
    static let epsilon = 1e-9
}

// MARK: - Trajectory

/// x(t) = topX + A·sin(ω·t + φ) + m·B·sin(ν·t + ψ)
struct AimParameters: Equatable {
    var width: Double
    var amplitude: Double
    var omega: Double
    var windAmplitude: Double
    var windOmega: Double
    var phi: Double
    var psi: Double
    var windFlips: Bool

    static func phases(seed: Int) -> (phi: Double, psi: Double) {
        let s = abs(seed)
        return (Double(s % 6283) / 1000.0, Double((s / 7) % 6283) / 1000.0)
    }

    /// m = (-1)^(floorCount // 2) for changing wind, otherwise 1.
    static func windMultiplier(floorCount: Int, flips: Bool) -> Double {
        guard flips else { return 1 }
        return (floorCount / 2) % 2 == 0 ? 1 : -1
    }

    func offset(at t: Double, floorCount: Int) -> Double {
        let m = Self.windMultiplier(floorCount: floorCount, flips: windFlips)
        return amplitude * sin(omega * t + phi) + m * windAmplitude * sin(windOmega * t + psi)
    }

    /// Sign of the current wind push for the indicator (+1 → right, −1 → left).
    func windDirection(at t: Double, floorCount: Int) -> Int {
        guard windAmplitude > 0 else { return 0 }
        let m = Self.windMultiplier(floorCount: floorCount, flips: windFlips)
        // Direction of the wind contribution's velocity.
        let v = m * windAmplitude * windOmega * cos(windOmega * t + psi)
        return v >= 0 ? 1 : -1
    }

    static func campaign(_ level: LevelConfig, seed: Int, timingAssist: Bool) -> AimParameters {
        let p = phases(seed: seed)
        let k = timingAssist ? RunRules.timingAssistFactor : 1
        return AimParameters(width: level.width,
                             amplitude: level.amplitude,
                             omega: level.angularSpeed * k,
                             windAmplitude: level.windAmplitude,
                             windOmega: level.windFrequency * k,
                             phi: p.phi, psi: p.psi,
                             windFlips: level.changingWind)
    }

    /// Free Build: W=180, A=70, ω=.95+min(n,60)·.008, B=min(14, n/3), ν=.55.
    static func freeBuild(floorCount n: Int, seed: Int, timingAssist: Bool) -> AimParameters {
        let p = phases(seed: seed)
        let k = timingAssist ? RunRules.timingAssistFactor : 1
        return AimParameters(width: 180,
                             amplitude: 70,
                             omega: (0.95 + Double(min(n, 60)) * 0.008) * k,
                             windAmplitude: min(14, Double(n) / 3.0),
                             windOmega: 0.55 * k,
                             phi: p.phi, psi: p.psi,
                             windFlips: false)
    }
}

// MARK: - Context

struct RunContext {
    var mode: RunMode
    var level: LevelConfig?
    /// Floors to place; nil = Free Build (up to the height limit).
    var targetFloors: Int?
    var heightLimit: Int = GameContent.freeBuildHeightLimit
    var width: Double = 180
    var perfectTolerance: Double = 0.045
    var maxStrain: Int = 100
    var braceThreshold: Int = 3
    var reduceMotion: Bool = false
    /// Facade asset for the floor with the given index (0 = lowest).
    var assetForIndex: (Int) -> String

    static func campaign(_ level: LevelConfig, reduceMotion: Bool, assetForIndex: @escaping (Int) -> String) -> RunContext {
        RunContext(mode: .campaign(levelID: level.id), level: level, targetFloors: level.targetFloors,
                   width: level.width, perfectTolerance: level.perfectTolerance, maxStrain: level.maxStrain,
                   braceThreshold: level.braceThreshold, reduceMotion: reduceMotion, assetForIndex: assetForIndex)
    }

    static func freeBuild(reduceMotion: Bool, assetForIndex: @escaping (Int) -> String) -> RunContext {
        RunContext(mode: .freeBuild, level: nil, targetFloors: nil, reduceMotion: reduceMotion, assetForIndex: assetForIndex)
    }

    static func tutorial(level: LevelConfig, reduceMotion: Bool, assetForIndex: @escaping (Int) -> String) -> RunContext {
        RunContext(mode: .tutorial, level: level,
                   targetFloors: RunRules.tutorialPresetFloors + RunRules.tutorialSteps,
                   width: level.width, perfectTolerance: level.perfectTolerance, maxStrain: level.maxStrain,
                   braceThreshold: level.braceThreshold, reduceMotion: reduceMotion, assetForIndex: assetForIndex)
    }

    func aimParameters(for s: RunSession) -> AimParameters {
        switch mode {
        case .campaign:
            return AimParameters.campaign(level!, seed: s.phaseSeed, timingAssist: s.timingAssist)
        case .freeBuild:
            return AimParameters.freeBuild(floorCount: s.floorCount, seed: s.phaseSeed, timingAssist: s.timingAssist)
        case .tutorial:
            var p = AimParameters.campaign(level!, seed: s.phaseSeed, timingAssist: s.timingAssist)
            p.omega *= RunRules.tutorialSlowFactor
            p.windAmplitude = 0
            return p
        }
    }

    var roofDuration: Double { reduceMotion ? RunRules.reducedMotionRoof : RunRules.roofInstall + RunRules.beaconOn }
    var beaconMoment: Double { reduceMotion ? RunRules.reducedMotionRoof / 2 : RunRules.roofInstall }

    func tutorialStep(_ s: RunSession) -> Int { max(0, s.floorCount - s.presetFloors) }
}

// MARK: - Commands and events

enum RunCommand: Equatable {
    /// Active (unpaused) time elapsed since the previous frame.
    case advance(dt: Double)
    /// Confirmed touchUpInside on Drop Floor.
    case release(commandID: UUID)
    case armBrace(commandID: UUID)
    case setPaused(Bool)
    case setTimingAssist(Bool)
}

enum RunEvent: Equatable {
    case aimingStarted(floorIndex: Int)
    case released(dx: Double, braced: Bool)
    case landed(kind: LandingKind, material: LandingMaterial, floorIndex: Int)
    /// streak after this landing; 3 means the triple was reached (brace may or may not charge).
    case perfect(streak: Int)
    case braceCharged
    case braceArmed
    case strainCrossed(threshold: Int)
    case missed
    case tooMuchStrain
    case tutorialRetry
    case failed(FailReason)
    case roofStarted
    case beaconLit
    case won
    case rejected
}

// MARK: - Reducer

/// Single sequential reducer for a run. Pure: no rendering, no randomness, no I/O.
struct RunEngine {
    let context: RunContext

    func aim(_ s: RunSession) -> AimParameters { context.aimParameters(for: s) }

    /// Current horizontal offset of the hanging floor relative to topX.
    func hangingOffset(_ s: RunSession) -> Double {
        switch s.stage {
        case .aiming:
            return aim(s).offset(at: s.stageTime, floorCount: s.floorCount)
        case .dropping, .failing:
            return s.planned?.dx ?? 0
        default:
            return 0
        }
    }

    func nextAsset(_ s: RunSession) -> String { context.assetForIndex(s.floorCount) }

    func canRelease(_ s: RunSession) -> Bool {
        guard s.stage == .aiming, !s.isPaused else { return false }
        if context.mode == .tutorial, context.tutorialStep(s) == RunRules.tutorialSteps - 1, !s.braceArmed {
            return false
        }
        return true
    }

    func canArmBrace(_ s: RunSession) -> Bool {
        s.stage == .aiming && !s.isPaused && s.braceCharged && !s.braceArmed
    }

    @discardableResult
    func reduce(_ s: inout RunSession, _ command: RunCommand) -> [RunEvent] {
        switch command {
        case .advance(let dt):
            return advance(&s, dt: dt)
        case .release(let id):
            guard !s.appliedCommandIDs.contains(id) else { return [] }
            guard canRelease(s) else { return [.rejected] }
            remember(id, in: &s)
            let braced = s.braceArmed
            let dx = braced ? 0 : aim(s).offset(at: s.stageTime, floorCount: s.floorCount)
            s.planned = PlannedPlacement(dx: dx, assetID: nextAsset(s), braced: braced, commandID: id)
            s.stage = .dropping
            s.stageTime = 0
            return [.released(dx: dx, braced: braced)]
        case .armBrace(let id):
            guard !s.appliedCommandIDs.contains(id) else { return [] }
            guard canArmBrace(s) else { return [.rejected] }
            remember(id, in: &s)
            s.braceCharged = false
            s.braceArmed = true
            return [.braceArmed]
        case .setPaused(let paused):
            if !s.stage.isTerminal { s.isPaused = paused }
            return []
        case .setTimingAssist(let on):
            guard !s.stage.isTerminal else { return [] }
            s.timingAssist = on
            if on { s.assisted = true }
            return []
        }
    }

    private func remember(_ id: UUID, in s: inout RunSession) {
        s.appliedCommandIDs.append(id)
        if s.appliedCommandIDs.count > 32 { s.appliedCommandIDs.removeFirst(s.appliedCommandIDs.count - 32) }
    }

    private func settleDuration(_ s: RunSession) -> Double {
        switch s.lastLanding {
        case .perfect?, .steady?: return RunRules.settlePerfect
        default: return RunRules.settleNormal
        }
    }

    private func advance(_ s: inout RunSession, dt: Double) -> [RunEvent] {
        guard dt > 0, dt.isFinite, !s.isPaused else { return [] }
        var remaining = dt
        var events: [RunEvent] = []
        var guardCounter = 0
        while remaining > 0, !s.stage.isTerminal, guardCounter < 64 {
            guardCounter += 1
            switch s.stage {
            case .aiming:
                s.stageTime += remaining
                s.simulationTime += remaining
                remaining = 0
            case .dropping:
                let need = RunRules.dropDuration - s.stageTime
                if remaining < need {
                    s.stageTime += remaining; s.simulationTime += remaining; remaining = 0
                } else {
                    s.simulationTime += max(0, need); remaining -= max(0, need)
                    events += resolve(&s)
                }
            case .settling:
                let need = settleDuration(s) - s.stageTime
                if remaining < need {
                    s.stageTime += remaining; s.simulationTime += remaining; remaining = 0
                } else {
                    s.simulationTime += max(0, need); remaining -= max(0, need)
                    events += afterSettle(&s)
                }
            case .failing:
                let need = RunRules.failingDuration - s.stageTime
                if remaining < need {
                    s.stageTime += remaining; s.simulationTime += remaining; remaining = 0
                } else {
                    s.simulationTime += max(0, need); remaining -= max(0, need)
                    if context.mode == .tutorial {
                        // Practice never fails: the same step simply starts again.
                        s.failReason = nil
                        s.planned = nil
                        s.stage = .aiming
                        s.stageTime = 0
                        events += [.tutorialRetry, .aimingStarted(floorIndex: s.floorCount)]
                    } else {
                        s.stage = .failed
                        s.stageTime = 0
                        events.append(.failed(s.failReason ?? .missedSupport))
                    }
                }
            case .roofing:
                let total = context.roofDuration
                let beacon = context.beaconMoment
                let before = s.stageTime
                let after = min(total, before + remaining)
                let used = after - before
                s.stageTime = after; s.simulationTime += used; remaining -= used
                if before < beacon && after >= beacon { events.append(.beaconLit) }
                if after >= total {
                    s.stage = .won
                    s.stageTime = 0
                    events.append(.won)
                    remaining = 0
                }
            case .won, .failed:
                remaining = 0
            }
        }
        return events
    }

    /// Called exactly once when the 350 ms fall ends.
    private func resolve(_ s: inout RunSession) -> [RunEvent] {
        guard let plan = s.planned else {
            s.stage = .aiming; s.stageTime = 0
            return [.aimingStarted(floorIndex: s.floorCount)]
        }
        let topX = s.topX
        let index = s.floorCount
        let material = LandingMaterial.of(asset: plan.assetID)

        if plan.braced {
            s.placements.append(Placement(centerX: topX, accuracy: 1, assetID: plan.assetID, kind: .steady))
            s.strain = max(0, s.strain - RunRules.braceRelief)
            s.streak = 0
            s.braceArmed = false
            s.braceUsed = true
            s.lastLanding = .steady
            s.planned = nil
            s.stage = .settling
            s.stageTime = 0
            return [.landed(kind: .steady, material: material, floorIndex: index)]
        }

        let r = abs(plan.dx) / context.width
        if r >= RunRules.missRatio - RunRules.epsilon {
            s.failReason = .missedSupport
            s.streak = 0
            s.stage = .failing
            s.stageTime = 0
            return [.missed]
        }

        if r <= context.perfectTolerance + RunRules.epsilon {
            s.placements.append(Placement(centerX: topX, accuracy: 1, assetID: plan.assetID, kind: .perfect))
            s.strain = max(0, s.strain - RunRules.perfectRelief)
            s.streak += 1
            var events: [RunEvent] = [.landed(kind: .perfect, material: material, floorIndex: index)]
            if s.streak >= context.braceThreshold {
                s.streak = 0
                if !s.braceCharged && !s.braceArmed {
                    s.braceCharged = true
                    events.append(.braceCharged)
                } else {
                    events.append(.perfect(streak: context.braceThreshold))
                }
            } else {
                events.append(.perfect(streak: s.streak))
            }
            s.lastLanding = .perfect
            s.planned = nil
            s.stage = .settling
            s.stageTime = 0
            return events
        }

        // Ordinary landing.
        let added = Int(ceil(max(0, r - context.perfectTolerance) * RunRules.strainFactor - RunRules.epsilon))
        let old = s.strain
        var newStrain = old + max(0, added)
        s.streak = 0
        var events: [RunEvent] = []
        if context.mode == .tutorial { newStrain = min(newStrain, context.maxStrain - 1) }
        let crossedWarning = old < RunRules.strainWarning && newStrain >= RunRules.strainWarning
        let crossedCritical = old < RunRules.strainCritical && newStrain >= RunRules.strainCritical
        if newStrain >= context.maxStrain {
            s.strain = context.maxStrain
            s.failReason = .tooMuchStrain
            s.lastLanding = .normal
            s.stage = .failing
            s.stageTime = 0
            events.append(.landed(kind: .normal, material: material, floorIndex: index))
            events.append(.tooMuchStrain)
            return events
        }
        s.strain = newStrain
        s.placements.append(Placement(centerX: topX + plan.dx, accuracy: max(0, 1 - r), assetID: plan.assetID, kind: .normal))
        s.lastLanding = .normal
        s.planned = nil
        s.stage = .settling
        s.stageTime = 0
        events.append(.landed(kind: .normal, material: material, floorIndex: index))
        if crossedCritical {
            events.append(.strainCrossed(threshold: RunRules.strainCritical))
        } else if crossedWarning {
            events.append(.strainCrossed(threshold: RunRules.strainWarning))
        }
        return events
    }

    private func afterSettle(_ s: inout RunSession) -> [RunEvent] {
        s.stageTime = 0
        var events: [RunEvent] = []
        let reachedTarget: Bool
        if let target = context.targetFloors {
            reachedTarget = s.floorCount >= target
        } else {
            reachedTarget = s.floorCount >= context.heightLimit
        }
        if reachedTarget {
            s.stage = .roofing
            events.append(.roofStarted)
            return events
        }
        if context.mode == .tutorial,
           context.tutorialStep(s) == RunRules.tutorialSteps - 1,
           !s.braceCharged, !s.braceArmed {
            s.braceCharged = true
            s.streak = 0
            events.append(.braceCharged)
        }
        s.stage = .aiming
        events.append(.aimingStarted(floorIndex: s.floorCount))
        return events
    }
}
