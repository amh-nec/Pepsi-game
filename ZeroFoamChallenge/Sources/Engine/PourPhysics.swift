import CoreGraphics
import Foundation

/// Where the falling stream ended up this frame.
enum ImpactKind {
    case none, wall, liquid, floor, spill
}

struct StreamTrace {
    /// Polyline of the stream, from the bottle mouth to the impact point.
    var points: [CGPoint]
    var impact: ImpactKind
    var impactPoint: CGPoint
    var impactSpeed: CGFloat
    /// 0 = perfect laminar pour, 1 = maximum froth.
    var foamFactor: CGFloat

    static let empty = StreamTrace(points: [], impact: .none,
                                   impactPoint: .zero, impactSpeed: 0, foamFactor: 0)
}

/// Pure simulation: no views, no drawing, no platform calls.
///
/// All volumes are fractions of the glass' nominal capacity (1.0 == 100%).
final class PourPhysics {
    var glass: GlassGeometry

    init(glass: GlassGeometry) { self.glass = glass }

    // MARK: Bottle state

    /// Bottle pivot in world coordinates.
    var bottlePos: CGPoint = .zero
    /// Bottle tilt in radians. 0 = upright (no flow), pi/2 = fully inverted.
    var bottleTilt: CGFloat = 0
    var bottleLength: CGFloat = 150

    // MARK: Fluid state

    private(set) var liquid: CGFloat = 0
    private(set) var foam: CGFloat = 0
    private(set) var wasted: CGFloat = 0

    /// Capacity fractions per second at full tilt.
    static let maxFlowRate: CGFloat = 0.42
    /// Tilt at which the bottle starts to pour.
    static let pourStartTilt: CGFloat = 0.55   // ~31 degrees
    static let pourFullTilt: CGFloat = 1.45    // ~83 degrees
    static let gravity: CGFloat = 2600         // points/s^2
    static let foamDecayRate: CGFloat = 0.16   // share of foam lost per second
    /// Share of collapsing foam that drains back into the liquid body.
    static let foamToLiquid: CGFloat = 0.45

    /// Smoothed flow, so the stream ramps instead of popping.
    private(set) var flow: CGFloat = 0
    private(set) var trace: StreamTrace = .empty

    var total: CGFloat { liquid + foam }
    var capacity: CGFloat { glass.spillCapacityFraction }
    var isOverflowing: Bool { total > capacity }
    var isPouring: Bool { flow > 0.02 }

    /// Foam share of everything poured so far, used for scoring.
    var foamRatio: CGFloat {
        let t = liquid + foam
        return t <= 0 ? 0 : min(max(foam / t, 0), 1)
    }

    var targetFlowRate: CGFloat {
        let raw = (abs(bottleTilt) - Self.pourStartTilt) / (Self.pourFullTilt - Self.pourStartTilt)
        let t = min(max(raw, 0), 1)
        // Ease in: a barely-tilted bottle trickles.
        return Self.maxFlowRate * (t * t * (3 - 2 * t))
    }

    /// World position of the bottle mouth (the end the liquid leaves).
    var mouth: CGPoint {
        let dir = CGPoint(x: sin(bottleTilt), y: cos(bottleTilt))
        return bottlePos + dir * (bottleLength * 0.5)
    }

    /// Exit velocity of the stream at the mouth.
    var exitVelocity: CGPoint {
        let speed = 40 + 220 * (targetFlowRate / Self.maxFlowRate)
        // The liquid leaves roughly along the bottle axis, but gravity always
        // pulls it down, so a near-upright bottle just dribbles straight down.
        let dir = CGPoint(x: sin(bottleTilt), y: cos(bottleTilt))
        let blended = CGPoint(x: dir.x, y: max(dir.y, 0.35))
        return blended / blended.length * speed
    }

    func reset() {
        liquid = 0
        foam = 0
        wasted = 0
        flow = 0
        trace = .empty
    }

    /// Seeds the fluid state directly. Only used by tests and previews.
    func seed(liquid: CGFloat, foam: CGFloat) {
        self.liquid = liquid
        self.foam = foam
    }

    /// Advances the simulation by `dt` seconds.
    func update(dt: CGFloat, active: Bool) {
        let target = active ? targetFlowRate : 0
        flow = approach(flow, target, rate: 11, dt: dt)
        if flow < 0.002 { flow = 0 }

        trace = traceStream()

        if flow > 0 {
            let poured = flow * dt
            switch trace.impact {
            case .spill, .none:
                wasted += poured
            case .wall, .liquid, .floor:
                let foamShare = trace.foamFactor
                foam += poured * foamShare
                liquid += poured * (1 - foamShare)
            }
        }

        // Foam always collapses: part drains back into the liquid, the rest
        // simply evaporates off the head.
        if foam > 0 {
            let collapsed = min(foam, foam * Self.foamDecayRate * dt + 0.0008 * dt)
            foam -= collapsed
            liquid += collapsed * Self.foamToLiquid
            if foam < 1e-5 { foam = 0 }
        }
    }

    // MARK: Stream tracing

    private func traceStream() -> StreamTrace {
        guard flow > 0 else { return .empty }

        let outline = glass.outline
        let surfaceY = glass.surfaceY(forFraction: min(max(total, 0), 1))

        var p = mouth
        var v = exitVelocity
        let step: CGFloat = 1.0 / 240.0
        var pts: [CGPoint] = [p]
        pts.reserveCapacity(64)

        for _ in 0..<260 {
            let next = CGPoint(x: p.x + v.x * step, y: p.y + v.y * step)
            let nv = CGPoint(x: v.x, y: v.y + Self.gravity * step)

            // 1. Crossing the liquid surface inside the glass.
            if p.y < surfaceY, next.y >= surfaceY {
                let t = (surfaceY - p.y) / (next.y - p.y)
                let hit = CGPoint(x: lerp(p.x, next.x, t), y: surfaceY)
                if let span = glass.span(atY: surfaceY), hit.x >= span.0, hit.x <= span.1 {
                    pts.append(hit)
                    return makeTrace(pts, .liquid, hit, v, nil)
                }
            }

            // 2. Clipping a glass wall.
            for wall in glass.walls {
                if let hit = Self.segmentIntersect(p, next, wall.0, wall.1) {
                    pts.append(hit)
                    // Only liquid already inside the glass can run down a wall;
                    // anything clipping the outside is spilled.
                    let inside = outline.contains(p)
                    return makeTrace(pts, inside ? .wall : .spill, hit, v, inside ? wall : nil)
                }
            }

            // 3. Dry glass: the stream reaches the base.
            let base = glass.floor
            if let baseHit = Self.segmentIntersect(p, next, base.0, base.1) {
                pts.append(baseHit)
                return makeTrace(pts, outline.contains(p) ? .floor : .spill, baseHit, v, nil)
            }

            p = next
            v = nv
            pts.append(p)

            // Fell past the glass entirely -> spilled on the table.
            if p.y > outline.maxY + 40 {
                return makeTrace(pts, .spill, p, v, nil)
            }
        }
        return makeTrace(pts, .spill, p, v, nil)
    }

    private func makeTrace(_ pts: [CGPoint],
                           _ kind: ImpactKind,
                           _ hit: CGPoint,
                           _ v: CGPoint,
                           _ wall: (CGPoint, CGPoint)?) -> StreamTrace {
        let speed = v.length
        var foamFactor: CGFloat

        switch kind {
        case .wall:
            // Grazing hits run down the wall as laminar flow -> almost no foam.
            // Slamming into the wall head on still froths.
            let w = wall!
            let wallDir = w.1 - w.0
            let len = wallDir.length
            let unit = len == 0 ? CGPoint(x: 0, y: 1) : wallDir / len
            let vUnit = speed == 0 ? CGPoint(x: 0, y: 1) : v / speed
            let cosA = abs(vUnit.x * unit.x + vUnit.y * unit.y)
            let sinA = sqrt(max(0, 1 - cosA * cosA))
            foamFactor = 0.05 + 0.75 * sinA
            // Sliding down a wall stays gentle even when fast.
            foamFactor *= 0.55 + 0.45 * min(max(speed / 900, 0), 1)
        case .liquid:
            // Straight down into the liquid is the worst case.
            let vUnit = speed == 0 ? CGPoint(x: 0, y: 1) : v / speed
            let verticality = min(max(abs(vUnit.y), 0), 1)
            let drop = min(max((speed - 180) / 700, 0), 1)
            foamFactor = (0.28 + 0.5 * verticality) * (0.55 + 0.65 * drop)
        case .floor:
            // Hitting the dry base is the classic foam disaster.
            foamFactor = 0.55 + 0.4 * min(max(speed / 900, 0), 1)
        case .spill, .none:
            foamFactor = 0
        }

        // A fat stream splashes more than a trickle.
        let intensity = min(max(flow / Self.maxFlowRate, 0), 1)
        foamFactor *= 0.65 + 0.5 * intensity

        return StreamTrace(points: pts,
                           impact: kind,
                           impactPoint: hit,
                           impactSpeed: speed,
                           foamFactor: min(max(foamFactor, 0), 0.95))
    }

    static func segmentIntersect(_ p1: CGPoint, _ p2: CGPoint,
                                 _ q1: CGPoint, _ q2: CGPoint) -> CGPoint? {
        let r = p2 - p1
        let s = q2 - q1
        let denom = r.x * s.y - r.y * s.x
        if abs(denom) < 1e-9 { return nil }
        let qp = q1 - p1
        let t = (qp.x * s.y - qp.y * s.x) / denom
        let u = (qp.x * r.y - qp.y * r.x) / denom
        if t < 0 || t > 1 || u < 0 || u > 1 { return nil }
        return CGPoint(x: p1.x + r.x * t, y: p1.y + r.y * t)
    }
}
