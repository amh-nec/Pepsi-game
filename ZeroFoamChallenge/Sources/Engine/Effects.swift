import CoreGraphics
import Foundation

struct Bubble {
    var pos: CGPoint
    var radius: CGFloat
    var speed: CGFloat
    var wobble: CGFloat
    var phase: CGFloat
    var alive = true
}

struct Droplet {
    var pos: CGPoint
    var vel: CGPoint
    var radius: CGFloat
    var life: CGFloat = 1
}

/// Purely cosmetic particle systems: fizzy bubbles inside the cola and splash
/// droplets at the impact point.
final class Effects {
    private(set) var bubbles: [Bubble] = []
    private(set) var droplets: [Droplet] = []

    private var bubbleAccumulator: CGFloat = 0
    private var rng = SystemRandomNumberGenerator()

    func clear() {
        bubbles.removeAll(keepingCapacity: true)
        droplets.removeAll(keepingCapacity: true)
    }

    private func rand() -> CGFloat { CGFloat.random(in: 0...1, using: &rng) }

    func spawnBubbles(dt: CGFloat, rate: CGFloat,
                      left: CGFloat, right: CGFloat,
                      bottomY: CGFloat, surfaceY: CGFloat) {
        guard right > left, bottomY > surfaceY else { return }
        bubbleAccumulator += rate * dt
        while bubbleAccumulator >= 1 {
            bubbleAccumulator -= 1
            let x = lerp(left, right, rand())
            let y = lerp(surfaceY, bottomY, 0.35 + rand() * 0.65)
            bubbles.append(Bubble(pos: CGPoint(x: x, y: y),
                                  radius: 1.2 + rand() * 2.6,
                                  speed: 26 + rand() * 52,
                                  wobble: 3 + rand() * 7,
                                  phase: rand() * .pi * 2))
        }
        if bubbles.count > 220 { bubbles.removeFirst(bubbles.count - 220) }
    }

    func splash(at point: CGPoint, strength: CGFloat) {
        let n = min(max(Int(strength * 3), 0), 4)
        for _ in 0..<n {
            let a = -CGFloat.pi / 2 + (rand() - 0.5) * 2.2
            let sp = 60 + rand() * 180 * strength
            droplets.append(Droplet(pos: point,
                                    vel: CGPoint(x: cos(a) * sp, y: sin(a) * sp),
                                    radius: 1.2 + rand() * 2.4))
        }
        if droplets.count > 120 { droplets.removeFirst(droplets.count - 120) }
    }

    func update(dt: CGFloat, surfaceY: CGFloat, gravity: CGFloat = 900) {
        for i in bubbles.indices {
            bubbles[i].phase += dt * bubbles[i].wobble
            bubbles[i].pos.x += sin(bubbles[i].phase) * 12 * dt
            bubbles[i].pos.y -= bubbles[i].speed * dt
            if bubbles[i].pos.y < surfaceY { bubbles[i].alive = false }
        }
        bubbles.removeAll { !$0.alive }

        for i in droplets.indices {
            droplets[i].vel.y += gravity * dt
            droplets[i].pos = droplets[i].pos + droplets[i].vel * dt
            droplets[i].life -= dt * 1.8
        }
        droplets.removeAll { $0.life <= 0 }
    }
}
