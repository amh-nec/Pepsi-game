import QuartzCore
import SwiftUI

/// Draws the whole playfield. Reads state, never mutates it — the SwiftUI
/// mirror of the Flutter CustomPainter.
struct GameCanvas: View {
    @ObservedObject var game: GameController

    var body: some View {
        // `frame` ticks once per display-link frame, which is what drives the
        // redraw; reading it here makes the dependency explicit.
        let _ = game.frame

        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            var ctx = context
            let shake = game.shake
            if shake > 0.01 {
                let t = CGFloat(CACurrentMediaTime())
                ctx.translateBy(x: sin(t * 47) * 7 * shake, y: cos(t * 39) * 5 * shake)
            }
            paintBackdrop(&ctx, size)
            paintTable(&ctx, size)
            paintGlass(&ctx, size)
            paintStream(&ctx)
            paintBottle(&ctx)
            paintDroplets(&ctx)
        }
        .ignoresSafeArea()
    }

    // MARK: Scenery

    private func paintBackdrop(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect),
                 with: .linearGradient(Gradient(colors: [Palette.bg1, Palette.bg2]),
                                       startPoint: .zero,
                                       endPoint: CGPoint(x: 0, y: size.height)))
        // Soft spotlight behind the glass.
        let c = game.glass.center
        let focus = CGPoint(x: c.x, y: c.y - game.glass.height * 0.5)
        let r = size.width * 0.55
        ctx.fill(Path(ellipseIn: CGRect(x: focus.x - r, y: focus.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(
                    Gradient(colors: [Palette.accent.opacity(0.13), Palette.accent.opacity(0)]),
                    center: focus, startRadius: 0, endRadius: r))
    }

    private func paintTable(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let y = game.glass.center.y
        let top = RoundedRectangle(cornerRadius: 8).path(in: CGRect(
            x: size.width * 0.06, y: y, width: size.width * 0.88, height: 16))
        // Contact shadow first, so the table edge stays crisp.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            let w = game.glass.bottomWidth * 1.9
            layer.fill(Path(ellipseIn: CGRect(x: game.glass.center.x - w / 2,
                                              y: y - 4, width: w, height: 16)),
                       with: .color(.black.opacity(0.45)))
        }
        ctx.fill(top, with: .color(Palette.table))
    }

    // MARK: Glass, liquid and foam

    private func paintGlass(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let g = game.glass
        let outline = g.outline
        let shape = Path(outline.path)

        ctx.fill(shape, with: .color(Palette.glassFill))

        let total = min(max(game.physics.total, 0), 1)
        let liquidFrac = min(max(game.physics.liquid, 0), 1)
        let surfaceY = g.surfaceY(forFraction: total)
        let liquidTopY = g.surfaceY(forFraction: liquidFrac)

        ctx.drawLayer { inner in
            inner.clip(to: shape)

            // Cola body: everything below the liquid line.
            if liquidFrac > 0.0005 {
                let body = Path(outline.clipBelow(liquidTopY).path)
                inner.fill(body, with: .linearGradient(
                    Gradient(colors: [Palette.colaLight, Palette.cola]),
                    startPoint: CGPoint(x: outline.minX, y: liquidTopY),
                    endPoint: CGPoint(x: outline.maxX, y: outline.maxY)))
                paintBubbles(&inner)
                if let span = g.span(atY: liquidTopY) {
                    // Meniscus highlight.
                    var line = Path()
                    line.move(to: CGPoint(x: span.0, y: liquidTopY))
                    line.addLine(to: CGPoint(x: span.1, y: liquidTopY))
                    inner.stroke(line, with: .color(Palette.colaLight.opacity(0.7)), lineWidth: 3)
                }
            }

            // Foam cap: the band between the foam top and the liquid line,
            // carved out by polygon clipping rather than a path subtraction,
            // which is iOS 17+.
            if game.physics.foam > 0.0005 {
                let band = Path(outline.clipBelow(surfaceY).clipAbove(liquidTopY).path)
                inner.fill(band, with: .color(Palette.foam))
                inner.stroke(band, with: .color(Palette.foamShade.opacity(0.55)), lineWidth: 2)
                paintFoamTop(&inner, g, surfaceY)
            }
        }

        // Rim + walls, with the danger pulse.
        let warn = game.isWarning
        let pulse = warn ? (0.55 + 0.45 * sin(game.warnPulse)) : 0
        let edgeColor = warn
            ? Palette.glassEdge.blend(Palette.danger, amount: 0.35 + 0.65 * pulse)
            : Palette.glassEdge
        if warn {
            ctx.drawLayer { glow in
                glow.addFilter(.blur(radius: 8))
                glow.stroke(shape, with: .color(Palette.danger.opacity(0.25 * pulse)), lineWidth: 10)
            }
        }
        ctx.stroke(shape, with: .color(edgeColor), lineWidth: warn ? 4 + 3 * pulse : 3)

        // Specular streak on the left wall.
        let a = outline.points[0], b = outline.points[3]
        var streak = Path()
        streak.move(to: CGPoint(x: lerp(a.x, b.x, 0.12) + 8, y: lerp(a.y, b.y, 0.12)))
        streak.addLine(to: CGPoint(x: lerp(a.x, b.x, 0.88) + 8, y: lerp(a.y, b.y, 0.88)))
        ctx.stroke(streak, with: .color(.white.opacity(0.18)),
                   style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    /// Bumpy froth silhouette, so the head never looks like a flat rectangle.
    private func paintFoamTop(_ ctx: inout GraphicsContext, _ g: GlassGeometry, _ y: CGFloat) {
        guard let span = g.span(atY: y) else { return }
        let w = span.1 - span.0
        let t = CGFloat(CACurrentMediaTime()) / 0.7
        var path = Path()
        path.move(to: CGPoint(x: span.0, y: y + 8))
        let bumps = 7
        for i in 0..<bumps {
            let x0 = span.0 + w * CGFloat(i) / CGFloat(bumps)
            let x1 = span.0 + w * CGFloat(i + 1) / CGFloat(bumps)
            let lift = 4 + 3 * sin(t + CGFloat(i) * 1.3)
            path.addQuadCurve(to: CGPoint(x: x1, y: y + 1),
                              control: CGPoint(x: (x0 + x1) / 2, y: y - lift))
        }
        path.addLine(to: CGPoint(x: span.1, y: y + 10))
        path.addLine(to: CGPoint(x: span.0, y: y + 10))
        path.closeSubpath()
        ctx.fill(path, with: .color(Palette.foam))
    }

    private func paintBubbles(_ ctx: inout GraphicsContext) {
        for b in game.effects.bubbles {
            let r = b.radius
            ctx.fill(Path(ellipseIn: CGRect(x: b.pos.x - r, y: b.pos.y - r,
                                            width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(0.45)))
        }
    }

    private func paintDroplets(_ ctx: inout GraphicsContext) {
        for d in game.effects.droplets {
            let r = d.radius
            ctx.fill(Path(ellipseIn: CGRect(x: d.pos.x - r, y: d.pos.y - r,
                                            width: r * 2, height: r * 2)),
                     with: .color(Palette.colaLight.opacity(Double(min(max(d.life, 0), 1)))))
        }
    }

    // MARK: Stream and bottle

    private func paintStream(_ ctx: inout GraphicsContext) {
        let trace = game.physics.trace
        guard trace.points.count > 1 else { return }
        let intensity = min(max(game.physics.flow / PourPhysics.maxFlowRate, 0), 1)
        var path = Path()
        path.addLines(trace.points)
        ctx.stroke(path, with: .color(Palette.cola),
                   style: StrokeStyle(lineWidth: 4 + 9 * intensity, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Palette.colaLight.opacity(0.8)),
                   style: StrokeStyle(lineWidth: 2 + 3 * intensity, lineCap: .round, lineJoin: .round))
    }

    private func paintBottle(_ ctx: inout GraphicsContext) {
        let p = game.physics
        ctx.drawLayer { layer in
            layer.translateBy(x: p.bottlePos.x, y: p.bottlePos.y)
            layer.rotate(by: .radians(Double(p.bottleTilt)))

            let h = p.bottleLength
            let w = h * 0.34
            let body = RoundedRectangle(cornerRadius: w * 0.28)
                .path(in: CGRect(x: -w / 2, y: -h * 0.5, width: w, height: h * 0.8))
            // The neck points down in local space (+y), matching `mouth`.
            let neck = RoundedRectangle(cornerRadius: w * 0.1)
                .path(in: CGRect(x: -w * 0.17, y: h * 0.28, width: w * 0.34, height: h * 0.22))
            let label = RoundedRectangle(cornerRadius: w * 0.08)
                .path(in: CGRect(x: -w * 0.36, y: -h * 0.16, width: w * 0.72, height: h * 0.3))

            layer.fill(body, with: .color(Palette.bottle))
            layer.fill(neck, with: .color(Palette.bottle))
            layer.fill(label, with: .color(Palette.label))
            layer.stroke(body, with: .color(.white.opacity(0.25)), lineWidth: 2)
        }
    }
}

extension Color {
    /// Simple linear blend, used for the warning rim.
    func blend(_ other: Color, amount: CGFloat) -> Color {
        let t = min(max(amount, 0), 1)
        #if canImport(UIKit)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: Double(lerp(r1, r2, t)),
                     green: Double(lerp(g1, g2, t)),
                     blue: Double(lerp(b1, b2, t)),
                     opacity: Double(lerp(a1, a2, t)))
        #else
        return t < 0.5 ? self : other
        #endif
    }
}
