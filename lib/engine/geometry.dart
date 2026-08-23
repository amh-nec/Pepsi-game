import 'dart:math' as math;
import 'dart:ui';

/// Small convex-polygon helpers used by both the physics engine and the
/// renderer. Everything works in logical pixels with y pointing *down*
/// (Flutter's canvas convention).
class Poly {
  const Poly(this.points);

  final List<Offset> points;

  double get area {
    double a = 0;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final q = points[(i + 1) % points.length];
      a += p.dx * q.dy - q.dx * p.dy;
    }
    return a.abs() / 2;
  }

  /// The part of this polygon that lies *below* the horizontal line `y`
  /// (below == larger y == liquid, since y grows downwards).
  Poly clipBelow(double y) {
    if (points.isEmpty) return const Poly(<Offset>[]);
    final out = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final cur = points[i];
      final nxt = points[(i + 1) % points.length];
      final curIn = cur.dy >= y;
      final nxtIn = nxt.dy >= y;
      if (curIn) out.add(cur);
      if (curIn != nxtIn) {
        final t = (y - cur.dy) / (nxt.dy - cur.dy);
        out.add(Offset(cur.dx + (nxt.dx - cur.dx) * t, y));
      }
    }
    return Poly(out);
  }

  Path toPath() {
    final p = Path();
    if (points.isEmpty) return p;
    p.moveTo(points.first.dx, points.first.dy);
    for (final pt in points.skip(1)) {
      p.lineTo(pt.dx, pt.dy);
    }
    p.close();
    return p;
  }

  bool contains(Offset q) {
    // Convex containment via consistent cross-product signs.
    int sign = 0;
    for (int i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final cross = (b.dx - a.dx) * (q.dy - a.dy) - (b.dy - a.dy) * (q.dx - a.dx);
      if (cross.abs() < 1e-9) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (sign != s) {
        return false;
      }
    }
    return true;
  }

  double get minY => points.map((p) => p.dy).reduce(math.min);
  double get maxY => points.map((p) => p.dy).reduce(math.max);
  double get minX => points.map((p) => p.dx).reduce(math.min);
  double get maxX => points.map((p) => p.dx).reduce(math.max);
}

/// A tilted drinking glass, modelled as a symmetric trapezoid rotated about
/// the centre of its base.
class GlassGeometry {
  GlassGeometry({
    required this.center,
    required this.height,
    required this.topWidth,
    required this.bottomWidth,
    this.tilt = 0,
  });

  /// Centre of the glass base, in world (canvas) coordinates.
  Offset center;
  double height;
  double topWidth;
  double bottomWidth;

  /// Tilt in radians. Positive tilts the glass mouth to the right.
  double tilt;

  /// Local-space corners, base centred on the origin, mouth at -y.
  List<Offset> get _local => <Offset>[
        Offset(-bottomWidth / 2, 0),
        Offset(bottomWidth / 2, 0),
        Offset(topWidth / 2, -height),
        Offset(-topWidth / 2, -height),
      ];

  Offset _toWorld(Offset p) {
    final c = math.cos(tilt), s = math.sin(tilt);
    return Offset(
      center.dx + p.dx * c - p.dy * s,
      center.dy + p.dx * s + p.dy * c,
    );
  }

  /// The glass outline in world coordinates: [bottomLeft, bottomRight,
  /// topRight, topLeft].
  Poly get outline => Poly(_local.map(_toWorld).toList(growable: false));

  Offset get rimLeft => outline.points[3];
  Offset get rimRight => outline.points[2];

  /// The lip the liquid pours over first when tilted: the *lower* of the two
  /// rim points (larger y).
  Offset get spillLip => rimLeft.dy >= rimRight.dy ? rimLeft : rimRight;

  /// Full upright volume, used as the reference "100% capacity".
  double get nominalArea => (topWidth + bottomWidth) / 2 * height;

  /// Fraction of nominal capacity that actually fits before liquid runs out
  /// over the lower lip at the current tilt. 1.0 when upright.
  double get spillCapacityFraction {
    final a = outline.clipBelow(spillLip.dy).area;
    return (a / nominalArea).clamp(0.0, 1.0);
  }

  /// World y of the horizontal liquid surface holding [fraction] of the
  /// nominal capacity. Solved by bisection on the clipped area.
  double surfaceYForFraction(double fraction) {
    final poly = outline;
    final target = fraction.clamp(0.0, 1.0) * nominalArea;
    if (target <= 0) return poly.maxY;
    double lo = poly.minY, hi = poly.maxY;
    for (int i = 0; i < 22; i++) {
      final mid = (lo + hi) / 2;
      if (poly.clipBelow(mid).area > target) {
        lo = mid; // too much liquid -> raise the cut line (larger y)
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  /// Horizontal span of the glass interior at world height [y].
  (double, double)? spanAtY(double y) {
    final poly = outline;
    if (y < poly.minY || y > poly.maxY) return null;
    double? lo, hi;
    final pts = poly.points;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      if ((a.dy - y) * (b.dy - y) > 0) continue;
      if ((b.dy - a.dy).abs() < 1e-9) continue;
      final t = (y - a.dy) / (b.dy - a.dy);
      final x = a.dx + (b.dx - a.dx) * t;
      lo = lo == null ? x : math.min(lo, x);
      hi = hi == null ? x : math.max(hi, x);
    }
    if (lo == null || hi == null) return null;
    return (lo, hi);
  }

  /// The two inner wall segments (left and right), world space.
  List<(Offset, Offset)> get walls => <(Offset, Offset)>[
        (outline.points[0], outline.points[3]), // bottom-left -> rim-left
        (outline.points[1], outline.points[2]), // bottom-right -> rim-right
      ];

  /// The base segment.
  (Offset, Offset) get floor => (outline.points[0], outline.points[1]);
}

double lerpD(double a, double b, double t) => a + (b - a) * t;

/// Frame-rate independent exponential smoothing.
double approach(double current, double target, double rate, double dt) {
  final t = 1 - math.exp(-rate * dt);
  return current + (target - current) * t;
}
