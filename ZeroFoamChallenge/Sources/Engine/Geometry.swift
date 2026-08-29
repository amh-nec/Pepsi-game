import CoreGraphics
import Foundation

/// Small convex-polygon helpers shared by the physics engine and the renderer.
/// Everything works in points with y pointing *down* (SwiftUI canvas space).
struct Poly {
    var points: [CGPoint]

    var area: CGFloat {
        guard points.count > 2 else { return 0 }
        var a: CGFloat = 0
        for i in points.indices {
            let p = points[i]
            let q = points[(i + 1) % points.count]
            a += p.x * q.y - q.x * p.y
        }
        return abs(a) / 2
    }

    /// The part of this polygon below the horizontal line `y`
    /// (below == larger y == liquid, since y grows downwards).
    func clipBelow(_ y: CGFloat) -> Poly {
        guard !points.isEmpty else { return Poly(points: []) }
        var out: [CGPoint] = []
        for i in points.indices {
            let cur = points[i]
            let nxt = points[(i + 1) % points.count]
            let curIn = cur.y >= y
            let nxtIn = nxt.y >= y
            if curIn { out.append(cur) }
            if curIn != nxtIn {
                let t = (y - cur.y) / (nxt.y - cur.y)
                out.append(CGPoint(x: cur.x + (nxt.x - cur.x) * t, y: y))
            }
        }
        return Poly(points: out)
    }

    /// The part of this polygon that lies *above* the horizontal line `y`.
    /// Together with `clipBelow` this carves out a horizontal band without
    /// needing path booleans, which are iOS 17+.
    func clipAbove(_ y: CGFloat) -> Poly {
        guard !points.isEmpty else { return Poly(points: []) }
        var out: [CGPoint] = []
        for i in points.indices {
            let cur = points[i]
            let nxt = points[(i + 1) % points.count]
            let curIn = cur.y <= y
            let nxtIn = nxt.y <= y
            if curIn { out.append(cur) }
            if curIn != nxtIn {
                let t = (y - cur.y) / (nxt.y - cur.y)
                out.append(CGPoint(x: cur.x + (nxt.x - cur.x) * t, y: y))
            }
        }
        return Poly(points: out)
    }

    var path: CGPath {
        let p = CGMutablePath()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }

    /// Convex containment via consistent cross-product signs.
    func contains(_ q: CGPoint) -> Bool {
        var sign = 0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let cross = (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x)
            if abs(cross) < 1e-9 { continue }
            let s = cross > 0 ? 1 : -1
            if sign == 0 { sign = s } else if sign != s { return false }
        }
        return true
    }

    var minY: CGFloat { points.map(\.y).min() ?? 0 }
    var maxY: CGFloat { points.map(\.y).max() ?? 0 }
    var minX: CGFloat { points.map(\.x).min() ?? 0 }
    var maxX: CGFloat { points.map(\.x).max() ?? 0 }
}

/// A tilted drinking glass, modelled as a symmetric trapezoid rotated about
/// the centre of its base.
final class GlassGeometry {
    /// Centre of the glass base, in canvas coordinates.
    var center: CGPoint
    var height: CGFloat
    var topWidth: CGFloat
    var bottomWidth: CGFloat
    /// Tilt in radians. Positive tilts the glass mouth to the right.
    var tilt: CGFloat

    init(center: CGPoint = .zero,
         height: CGFloat = 260,
         topWidth: CGFloat = 150,
         bottomWidth: CGFloat = 118,
         tilt: CGFloat = 0) {
        self.center = center
        self.height = height
        self.topWidth = topWidth
        self.bottomWidth = bottomWidth
        self.tilt = tilt
    }

    /// Local-space corners: base centred on the origin, mouth at -y.
    private var localCorners: [CGPoint] {
        [
            CGPoint(x: -bottomWidth / 2, y: 0),
            CGPoint(x: bottomWidth / 2, y: 0),
            CGPoint(x: topWidth / 2, y: -height),
            CGPoint(x: -topWidth / 2, y: -height)
        ]
    }

    private func toWorld(_ p: CGPoint) -> CGPoint {
        let c = cos(tilt), s = sin(tilt)
        return CGPoint(x: center.x + p.x * c - p.y * s,
                       y: center.y + p.x * s + p.y * c)
    }

    /// Outline in world space: [bottomLeft, bottomRight, rimRight, rimLeft].
    var outline: Poly { Poly(points: localCorners.map(toWorld)) }

    var rimLeft: CGPoint { outline.points[3] }
    var rimRight: CGPoint { outline.points[2] }

    /// The lip the liquid pours over first when tilted: the *lower* rim point.
    var spillLip: CGPoint { rimLeft.y >= rimRight.y ? rimLeft : rimRight }

    /// Full upright volume, the reference "100% capacity".
    var nominalArea: CGFloat { (topWidth + bottomWidth) / 2 * height }

    /// Fraction of nominal capacity that fits before liquid runs out over the
    /// lower lip at the current tilt. 1.0 when upright.
    var spillCapacityFraction: CGFloat {
        min(1, max(0, outline.clipBelow(spillLip.y).area / nominalArea))
    }

    /// World y of the horizontal liquid surface holding `fraction` of the
    /// nominal capacity. Solved by bisection on the clipped area.
    func surfaceY(forFraction fraction: CGFloat) -> CGFloat {
        let poly = outline
        let target = min(max(fraction, 0), 1) * nominalArea
        if target <= 0 { return poly.maxY }
        var lo = poly.minY, hi = poly.maxY
        for _ in 0..<22 {
            let mid = (lo + hi) / 2
            // Area below the cut shrinks as the cut moves down (larger y).
            if poly.clipBelow(mid).area > target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Horizontal span of the glass interior at world height `y`.
    func span(atY y: CGFloat) -> (CGFloat, CGFloat)? {
        let poly = outline
        guard y >= poly.minY, y <= poly.maxY else { return nil }
        var lo: CGFloat?, hi: CGFloat?
        let pts = poly.points
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            if (a.y - y) * (b.y - y) > 0 { continue }
            if abs(b.y - a.y) < 1e-9 { continue }
            let t = (y - a.y) / (b.y - a.y)
            let x = a.x + (b.x - a.x) * t
            lo = lo.map { min($0, x) } ?? x
            hi = hi.map { max($0, x) } ?? x
        }
        guard let l = lo, let h = hi else { return nil }
        return (l, h)
    }

    /// The two inner wall segments (left and right), world space.
    var walls: [(CGPoint, CGPoint)] {
        let o = outline.points
        return [(o[0], o[3]), (o[1], o[2])]
    }

    /// The base segment.
    var floor: (CGPoint, CGPoint) {
        let o = outline.points
        return (o[0], o[1])
    }
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// Frame-rate independent exponential smoothing.
func approach(_ current: CGFloat, _ target: CGFloat, rate: CGFloat, dt: CGFloat) -> CGFloat {
    let t = 1 - exp(-rate * dt)
    return current + (target - current) * t
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func / (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x / s, y: a.y / s) }
    var length: CGFloat { sqrt(x * x + y * y) }
}
