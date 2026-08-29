import Combine
import CoreGraphics
import Foundation
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

enum GamePhase {
    case menu, playing, success, gameOver
}

enum ControlMode {
    case touch, tilt
}

struct RoundResult {
    let score: Int
    let liquid: CGFloat
    let foam: CGFloat
    let timeUsed: CGFloat
    let multiplier: CGFloat
    let reason: String
}

/// Owns the game loop, the round rules and every piece of mutable state the UI
/// needs. The physics itself lives in `PourPhysics`; this only decides *when*
/// things happen.
final class GameController: ObservableObject {
    static let roundSeconds: CGFloat = 30
    static let targetLiquid: CGFloat = 0.90
    static let warnThreshold: CGFloat = 0.90

    let glass = GlassGeometry()
    lazy var physics = PourPhysics(glass: glass)
    let effects = Effects()
    let haptics = Haptics()
    let audio = GameAudio()
    private let motion = MotionInput()

    /// Bumped every frame; SwiftUI redraws the canvas and HUD from it.
    @Published private(set) var frame: Int = 0
    @Published private(set) var phase: GamePhase = .menu
    @Published var controlMode: ControlMode = .touch
    @Published private(set) var sensorAvailable = false

    private(set) var timeLeft: CGFloat = GameController.roundSeconds
    private(set) var bestScore = 0
    private(set) var lastResult: RoundResult?

    /// Player input, normalised by the view layer.
    var glassTiltInput: CGFloat = 0    // -1...1
    var bottleTiltInput: CGFloat = 0   // 0...1
    var bottleXInput: CGFloat = 0.5    // 0...1 across the playfield

    private var smoothedBottleX: CGFloat = 0.5
    private var smoothedBottleTilt: CGFloat = 0
    private var smoothedGlassTilt: CGFloat = 0

    /// Cosmetic feedback state read by the renderer.
    private(set) var shake: CGFloat = 0
    private(set) var warnPulse: CGFloat = 0
    private(set) var viewport: CGSize = .zero

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    var isWarning: Bool {
        phase == .playing && physics.total >= Self.warnThreshold * physics.capacity
    }

    // MARK: Lifecycle

    func boot() {
        audio.start()
        haptics.prepare()
        motion.onTilt = { [weak self] tilt in
            guard let self else { return }
            if !self.sensorAvailable { self.sensorAvailable = true }
            if self.controlMode == .tilt { self.glassTiltInput = tilt }
        }
        motion.start()
        startLoop()
    }

    func shutdown() {
        stopLoop()
        motion.stop()
        audio.shutdown()
    }

    func layout(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        viewport = size
        let usableH = size.height - safeTop - safeBottom
        let h = min(max(usableH * 0.34, 180), 340)
        glass.height = h
        glass.topWidth = h * 0.58
        glass.bottomWidth = h * 0.46
        glass.center = CGPoint(x: size.width * 0.5,
                               y: size.height - safeBottom - usableH * 0.16)
        physics.bottleLength = h * 0.86
    }

    func startRound() {
        physics.reset()
        effects.clear()
        timeLeft = Self.roundSeconds
        shake = 0
        warnPulse = 0
        glassTiltInput = 0
        bottleTiltInput = 0
        bottleXInput = 0.5
        smoothedBottleX = 0.5
        smoothedBottleTilt = 0
        smoothedGlassTilt = 0
        lastResult = nil
        phase = .playing
    }

    func toMenu() {
        phase = .menu
        audio.stopAll()
    }

    func setControlMode(_ mode: ControlMode) {
        controlMode = mode
        if mode == .touch { glassTiltInput = 0 }
    }

    // MARK: Loop

    private func startLoop() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy { [weak self] link in
            self?.tick(link)
        }, selector: #selector(DisplayLinkProxy.step(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = link.timestamp }
        // Clamp so a dropped frame or a resume from background never
        // teleports the simulation.
        var dt = CGFloat(link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp
        dt = min(max(dt, 0), 1.0 / 30.0)
        guard dt > 0 else { return }

        if phase == .playing {
            stepPlaying(dt: dt)
        } else {
            shake = approach(shake, 0, rate: 6, dt: dt)
            effects.update(dt: dt, surfaceY: glass.surfaceY(forFraction: physics.total))
        }
        frame &+= 1
    }

    private func stepPlaying(dt: CGFloat) {
        // Smooth the raw input so both gyro jitter and finger jumps feel silky.
        smoothedGlassTilt = approach(smoothedGlassTilt, glassTiltInput * 0.62, rate: 9, dt: dt)
        smoothedBottleTilt = approach(smoothedBottleTilt, bottleTiltInput * 1.75, rate: 10, dt: dt)
        smoothedBottleX = approach(smoothedBottleX, bottleXInput, rate: 12, dt: dt)

        glass.tilt = smoothedGlassTilt

        let w = viewport.width
        physics.bottleTilt = smoothedBottleTilt
        physics.bottlePos = CGPoint(
            x: lerp(w * 0.16, w * 0.84, min(max(smoothedBottleX, 0), 1)),
            y: glass.center.y - glass.height - viewport.height * 0.13
        )

        physics.update(dt: dt, active: true)

        updateFeedback(dt: dt)
        updateEffects(dt: dt)

        timeLeft -= dt

        if physics.isOverflowing {
            endRound(success: false, reason: "OVERFLOW!")
        } else if physics.liquid >= Self.targetLiquid && !physics.isPouring {
            endRound(success: true, reason: "PERFECT POUR")
        } else if timeLeft <= 0 {
            timeLeft = 0
            let ok = physics.liquid >= Self.targetLiquid
            endRound(success: ok, reason: ok ? "JUST IN TIME" : "TIME'S UP")
        }
    }

    private func updateFeedback(dt: CGFloat) {
        let pouring = physics.isPouring
        let intensity = min(max(physics.flow / PourPhysics.maxFlowRate, 0), 1)
        audio.setPouring(pouring, intensity: intensity)
        if pouring { haptics.pourTick(intensity: intensity) }

        if isWarning {
            warnPulse += dt * 7
            shake = max(shake, 0.35)
            haptics.warning()
        } else {
            warnPulse = 0
        }
        shake = approach(shake, 0, rate: 5, dt: dt)
    }

    private func updateEffects(dt: CGFloat) {
        let surfaceY = glass.surfaceY(forFraction: physics.total)
        if let span = glass.span(atY: surfaceY + 6), physics.liquid > 0.02 {
            effects.spawnBubbles(dt: dt,
                                 rate: 14 + 60 * physics.flow / PourPhysics.maxFlowRate,
                                 left: span.0 + 6,
                                 right: span.1 - 6,
                                 bottomY: glass.outline.maxY - 4,
                                 surfaceY: surfaceY)
        }
        let trace = physics.trace
        switch trace.impact {
        case .liquid, .floor, .wall:
            effects.splash(at: trace.impactPoint, strength: trace.foamFactor * 1.2)
        default:
            break
        }
        effects.update(dt: dt, surfaceY: surfaceY)
    }

    private func endRound(success: Bool, reason: String) {
        audio.stopAll()
        let timeUsed = Self.roundSeconds - timeLeft
        let remaining = min(max(Self.roundSeconds - timeUsed, 0), Self.roundSeconds)
        let speedBonus = success ? 1 + remaining / Self.roundSeconds : 1
        let purity = min(max(1 - physics.foamRatio, 0), 1)
        let precision = success ? 1 + purity * 1.5 : 0.4
        let multiplier = speedBonus * precision
        let base = success ? 1000 * min(max(physics.liquid, 0), 1) : 250 * physics.liquid
        let score = Int((base * multiplier).rounded())

        lastResult = RoundResult(score: score,
                                 liquid: physics.liquid,
                                 foam: physics.foam,
                                 timeUsed: timeUsed,
                                 multiplier: multiplier,
                                 reason: reason)
        bestScore = max(bestScore, score)
        phase = success ? .success : .gameOver

        if success {
            haptics.success()
            audio.playSuccess()
        } else {
            shake = 1.4
            haptics.error()
            audio.playFail()
        }
    }
}

/// CADisplayLink retains its target, so the controller hands it a proxy
/// instead of itself and keeps the retain cycle out of the way.
private final class DisplayLinkProxy: NSObject {
    private let handler: (CADisplayLink) -> Void

    init(_ handler: @escaping (CADisplayLink) -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func step(_ link: CADisplayLink) { handler(link) }
}
