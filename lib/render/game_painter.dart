import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/game_controller.dart';
import '../engine/geometry.dart';
import '../engine/physics.dart';

class Palette {
  static const bg1 = Color(0xFF12203A);
  static const bg2 = Color(0xFF07101F);
  static const cola = Color(0xFF3A1408);
  static const colaLight = Color(0xFF7A2E10);
  static const foam = Color(0xFFFFF4E2);
  static const foamShade = Color(0xFFE3CBA9);
  static const glass = Color(0x33FFFFFF);
  static const glassEdge = Color(0xCCE8F4FF);
  static const bottle = Color(0xFF1D3F2A);
  static const label = Color(0xFFE23B3B);
  static const accent = Color(0xFFFFD166);
  static const danger = Color(0xFFFF4D4D);
}

/// Draws the whole playfield. Reads state, never mutates it.
class GamePainter extends CustomPainter {
  GamePainter(this.game) : super(repaint: game);

  final GameController game;

  @override
  void paint(Canvas canvas, Size size) {
    final shake = game.shake;
    if (shake > 0.01) {
      final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
      canvas.save();
      canvas.translate(
        math.sin(t * 47) * 7 * shake,
        math.cos(t * 39) * 5 * shake,
      );
    }

    _paintBackdrop(canvas, size);
    _paintTable(canvas, size);
    _paintGlass(canvas, size);
    _paintStream(canvas);
    _paintBottle(canvas, size);
    _paintDroplets(canvas);

    if (shake > 0.01) canvas.restore();
  }

  // ---- Scenery ------------------------------------------------------------

  void _paintBackdrop(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.bg1, Palette.bg2],
        ).createShader(rect),
    );
    // Soft spotlight behind the glass.
    final c = game.glass.center;
    canvas.drawCircle(
      Offset(c.dx, c.dy - game.glass.height * 0.5),
      size.width * 0.55,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(c.dx, c.dy - game.glass.height * 0.5),
          size.width * 0.55,
          [const Color(0x22FFD166), const Color(0x00FFD166)],
        ),
    );
  }

  void _paintTable(Canvas canvas, Size size) {
    final y = game.glass.center.dy;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.06, y, size.width * 0.88, 16),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFF2A3D5C),
    );
    // Contact shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(game.glass.center.dx, y + 4),
        width: game.glass.bottomWidth * 1.9,
        height: 16,
      ),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  // ---- Glass, liquid and foam --------------------------------------------

  void _paintGlass(Canvas canvas, Size size) {
    final g = game.glass;
    final outline = g.outline;
    final path = outline.toPath();

    // Glass body.
    canvas.drawPath(path, Paint()..color = Palette.glass);

    final total = game.physics.total.clamp(0.0, 1.0);
    final liquidFrac = game.physics.liquid.clamp(0.0, 1.0);
    final surfaceY = g.surfaceYForFraction(total);
    final liquidTopY = g.surfaceYForFraction(liquidFrac);

    canvas.save();
    canvas.clipPath(path);

    // Cola body (everything below the liquid line).
    if (liquidFrac > 0.0005) {
      final body = outline.clipBelow(liquidTopY);
      canvas.drawPath(
        body.toPath(),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(outline.minX, liquidTopY),
            Offset(outline.maxX, outline.maxY),
            [Palette.colaLight, Palette.cola],
          ),
      );
      _paintBubbles(canvas);
      // Meniscus highlight.
      _paintSurfaceLine(canvas, g, liquidTopY, Palette.colaLight.withValues(alpha: 0.7));
    }

    // Foam cap: sits between the foam top and the liquid line.
    if (game.physics.foam > 0.0005) {
      final foamBand = Path.combine(
        PathOperation.difference,
        outline.clipBelow(surfaceY).toPath(),
        outline.clipBelow(liquidTopY).toPath(),
      );
      canvas.drawPath(foamBand, Paint()..color = Palette.foam);
      canvas.drawPath(
        foamBand,
        Paint()
          ..color = Palette.foamShade.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _paintFoamTop(canvas, g, surfaceY);
    }

    canvas.restore();

    // Rim + walls.
    final warn = game.isWarning;
    final pulse = warn ? (0.55 + 0.45 * math.sin(game.warnPulse)) : 0.0;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = warn ? 4 + 3 * pulse : 3
        ..color = warn
            ? Color.lerp(Palette.glassEdge, Palette.danger, 0.35 + 0.65 * pulse)!
            : Palette.glassEdge,
    );
    if (warn) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = Palette.danger.withValues(alpha: 0.25 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Specular streak on the left wall.
    final a = outline.points[0], b = outline.points[3];
    canvas.drawLine(
      Offset.lerp(a, b, 0.12)!.translate(8, 0),
      Offset.lerp(a, b, 0.88)!.translate(8, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintSurfaceLine(Canvas canvas, GlassGeometry g, double y, Color color) {
    final span = g.spanAtY(y);
    if (span == null) return;
    canvas.drawLine(
      Offset(span.$1, y),
      Offset(span.$2, y),
      Paint()
        ..color = color
        ..strokeWidth = 3,
    );
  }

  /// Bumpy froth silhouette so the head never looks like a flat rectangle.
  void _paintFoamTop(Canvas canvas, GlassGeometry g, double y) {
    final span = g.spanAtY(y);
    if (span == null) return;
    final path = Path()..moveTo(span.$1, y + 8);
    const bumps = 7;
    final w = span.$2 - span.$1;
    final t = DateTime.now().millisecondsSinceEpoch / 700.0;
    for (int i = 0; i < bumps; i++) {
      final x0 = span.$1 + w * i / bumps;
      final x1 = span.$1 + w * (i + 1) / bumps;
      final lift = 4 + 3 * math.sin(t + i * 1.3);
      path.quadraticBezierTo((x0 + x1) / 2, y - lift, x1, y + 1);
    }
    path
      ..lineTo(span.$2, y + 10)
      ..lineTo(span.$1, y + 10)
      ..close();
    canvas.drawPath(path, Paint()..color = Palette.foam);
  }

  void _paintBubbles(Canvas canvas) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.45);
    for (final b in game.effects.bubbles) {
      canvas.drawCircle(b.pos, b.radius, paint);
    }
  }

  void _paintDroplets(Canvas canvas) {
    for (final d in game.effects.droplets) {
      canvas.drawCircle(
        d.pos,
        d.radius,
        Paint()..color = Palette.colaLight.withValues(alpha: d.life.clamp(0.0, 1.0)),
      );
    }
  }

  // ---- Stream and bottle --------------------------------------------------

  void _paintStream(Canvas canvas) {
    final trace = game.physics.trace;
    if (trace.points.length < 2) return;
    final intensity = (game.physics.flow / PourPhysics.maxFlowRate).clamp(0.0, 1.0);
    final path = Path()..moveTo(trace.points.first.dx, trace.points.first.dy);
    for (final p in trace.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 4 + 9 * intensity
        ..color = Palette.cola,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2 + 3 * intensity
        ..color = Palette.colaLight.withValues(alpha: 0.8),
    );
  }

  void _paintBottle(Canvas canvas, Size size) {
    final p = game.physics;
    canvas.save();
    canvas.translate(p.bottlePos.dx, p.bottlePos.dy);
    canvas.rotate(p.bottleTilt);

    final h = p.bottleLength;
    final w = h * 0.34;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(-w / 2, -h * 0.5, w, h * 0.8),
      Radius.circular(w * 0.28),
    );
    canvas.drawRRect(body, Paint()..color = Palette.bottle);
    // Neck + mouth point downwards in local space (+y).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-w * 0.17, h * 0.28, w * 0.34, h * 0.22),
        Radius.circular(w * 0.1),
      ),
      Paint()..color = Palette.bottle,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-w * 0.36, -h * 0.16, w * 0.72, h * 0.3),
        Radius.circular(w * 0.08),
      ),
      Paint()..color = Palette.label,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.25),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
