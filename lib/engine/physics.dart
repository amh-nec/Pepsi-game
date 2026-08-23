import 'dart:math' as math;
import 'dart:ui';

import 'geometry.dart';

/// Where the falling stream ended up this frame.
enum ImpactKind { none, wall, liquid, floor, spill }

class StreamTrace {
  StreamTrace({
    required this.points,
    required this.impact,
    required this.impactPoint,
    required this.impactSpeed,
    required this.foamFactor,
  });

  /// Polyline of the stream, from the bottle mouth to the impact point.
  final List<Offset> points;
  final ImpactKind impact;
  final Offset impactPoint;
  final double impactSpeed;

  /// 0 = perfect laminar pour, 1 = maximum froth.
  final double foamFactor;

  static StreamTrace empty = StreamTrace(
    points: const <Offset>[],
    impact: ImpactKind.none,
    impactPoint: Offset.zero,
    impactSpeed: 0,
    foamFactor: 0,
  );
}

/// Pure simulation: no widgets, no painting, no platform calls.
///
/// All volumes are fractions of the glass' nominal capacity (1.0 == 100%).
class PourPhysics {
  PourPhysics({required this.glass});

  GlassGeometry glass;

  // ---- Bottle state -------------------------------------------------------
  /// Bottle mouth pivot in world coordinates.
  Offset bottlePos = Offset.zero;

  /// Bottle tilt in radians. 0 = upright (no flow), pi/2 = fully inverted.
  double bottleTilt = 0;

  double bottleLength = 150;

  // ---- Fluid state --------------------------------------------------------
  double liquid = 0;
  double foam = 0;
  double wasted = 0;

  /// Litres/second-ish, expressed in capacity fractions per second.
  static const double maxFlowRate = 0.42;

  /// Tilt at which the bottle starts to pour.
  static const double pourStartTilt = 0.55; // ~31 degrees
  static const double pourFullTilt = 1.45; // ~83 degrees

  static const double gravity = 2600; // px/s^2
  static const double foamDecayRate = 0.16; // fraction of foam lost per second
  static const double foamToLiquid = 0.45; // share of collapsing foam that
  // returns to the liquid body

  /// Smoothed flow, so the stream ramps up/down instead of popping.
  double _flow = 0;
  double get flow => _flow;

  StreamTrace trace = StreamTrace.empty;

  double get total => liquid + foam;
  double get capacity => glass.spillCapacityFraction;
  bool get isOverflowing => total > capacity;
  bool get isPouring => _flow > 0.02;

  /// Foam share of what has been poured so far, used for scoring.
  double get foamRatio {
    final t = liquid + foam;
    return t <= 0 ? 0 : (foam / t).clamp(0.0, 1.0);
  }

  double get targetFlowRate {
    final t = ((bottleTilt.abs() - pourStartTilt) /
            (pourFullTilt - pourStartTilt))
        .clamp(0.0, 1.0);
    // Ease in: a barely-tilted bottle trickles.
    return maxFlowRate * (t * t * (3 - 2 * t));
  }

  /// World position of the bottle's mouth (the end that the liquid leaves).
  Offset get mouth {
    final dir = Offset(math.sin(bottleTilt), math.cos(bottleTilt));
    return bottlePos + dir * (bottleLength * 0.5);
  }

  /// Exit velocity of the stream at the mouth.
  Offset get exitVelocity {
    final speed = 40 + 220 * (targetFlowRate / maxFlowRate);
    // The liquid leaves roughly along the bottle's axis, but gravity always
    // pulls it down, so a near-upright bottle just dribbles straight down.
    final dir = Offset(math.sin(bottleTilt), math.cos(bottleTilt));
    final blended = Offset(dir.dx, math.max(dir.dy, 0.35));
    final len = blended.distance;
    return blended / len * speed;
  }

  void resize(GlassGeometry g) => glass = g;

  void reset() {
    liquid = 0;
    foam = 0;
    wasted = 0;
    _flow = 0;
    trace = StreamTrace.empty;
  }

  /// Advances the simulation by [dt] seconds. Returns the trace so the
  /// renderer never has to recompute anything.
  void update(double dt, {required bool active}) {
    final target = active ? targetFlowRate : 0.0;
    _flow = approach(_flow, target, 11, dt);
    if (_flow < 0.002) _flow = 0;

    trace = _traceStream();

    if (_flow > 0) {
      final poured = _flow * dt;
      switch (trace.impact) {
        case ImpactKind.spill:
        case ImpactKind.none:
          wasted += poured;
        case ImpactKind.wall:
        case ImpactKind.liquid:
        case ImpactKind.floor:
          final foamShare = trace.foamFactor;
          foam += poured * foamShare;
          liquid += poured * (1 - foamShare);
      }
    }

    // Foam always collapses: part of it drains back into the liquid, the rest
    // simply evaporates into the head.
    if (foam > 0) {
      final collapsed = math.min(foam, foam * foamDecayRate * dt + 0.0008 * dt);
      foam -= collapsed;
      liquid += collapsed * foamToLiquid;
      if (foam < 1e-5) foam = 0;
    }
  }

  // ---- Stream tracing -----------------------------------------------------

  StreamTrace _traceStream() {
    if (_flow <= 0) return StreamTrace.empty;

    final outline = glass.outline;
    final surfaceY = glass.surfaceYForFraction(total.clamp(0.0, 1.0));

    var p = mouth;
    var v = exitVelocity;
    const step = 1 / 240.0;
    final pts = <Offset>[p];

    for (int i = 0; i < 260; i++) {
      final next = Offset(p.dx + v.dx * step, p.dy + v.dy * step);
      final nv = Offset(v.dx, v.dy + gravity * step);

      // 1. Did we cross the liquid surface inside the glass?
      if (p.dy < surfaceY && next.dy >= surfaceY) {
        final span = glass.spanAtY(surfaceY);
        final t = (surfaceY - p.dy) / (next.dy - p.dy);
        final hit = Offset(lerpD(p.dx, next.dx, t), surfaceY);
        if (span != null && hit.dx >= span.$1 && hit.dx <= span.$2) {
          pts.add(hit);
          return _makeTrace(pts, ImpactKind.liquid, hit, v, null);
        }
      }

      // 2. Did we clip one of the glass walls?
      for (final wall in glass.walls) {
        final hit = _segmentIntersect(p, next, wall.$1, wall.$2);
        if (hit != null) {
          pts.add(hit);
          // Only liquid that is already inside the glass can run down a wall;
          // anything clipping the outside of the glass is spilled.
          final inside = outline.contains(p);
          return _makeTrace(
            pts,
            inside ? ImpactKind.wall : ImpactKind.spill,
            hit,
            v,
            inside ? wall : null,
          );
        }
      }

      // 3. Dry glass: the stream reaches the base.
      final base = glass.floor;
      final baseHit = _segmentIntersect(p, next, base.$1, base.$2);
      if (baseHit != null) {
        pts.add(baseHit);
        return _makeTrace(
          pts,
          outline.contains(p) ? ImpactKind.floor : ImpactKind.spill,
          baseHit,
          v,
          null,
        );
      }

      p = next;
      v = nv;
      pts.add(p);

      // Fell past the glass entirely -> spilled on the table.
      if (p.dy > outline.maxY + 40) {
        return _makeTrace(pts, ImpactKind.spill, p, v, null);
      }
    }
    return _makeTrace(pts, ImpactKind.spill, p, v, null);
  }

  StreamTrace _makeTrace(
    List<Offset> pts,
    ImpactKind kind,
    Offset hit,
    Offset v,
    (Offset, Offset)? wall,
  ) {
    final speed = v.distance;
    double foamFactor;

    switch (kind) {
      case ImpactKind.wall:
        // Grazing hits run down the wall as laminar flow -> almost no foam.
        // Slamming into the wall head on still froths.
        final w = wall!;
        final wallDir = (w.$2 - w.$1);
        final wLen = wallDir.distance;
        final unit = wLen == 0 ? const Offset(0, 1) : wallDir / wLen;
        final vUnit = speed == 0 ? const Offset(0, 1) : v / speed;
        final cosA = (vUnit.dx * unit.dx + vUnit.dy * unit.dy).abs();
        final sinA = math.sqrt(math.max(0, 1 - cosA * cosA));
        foamFactor = 0.05 + 0.75 * sinA;
        // Sliding down a wall into the liquid stays gentle even when fast.
        foamFactor *= 0.55 + 0.45 * (speed / 900).clamp(0.0, 1.0);
      case ImpactKind.liquid:
        // Straight down into the liquid is the worst case.
        final vUnit = speed == 0 ? const Offset(0, 1) : v / speed;
        final verticality = vUnit.dy.abs().clamp(0.0, 1.0);
        final drop = ((speed - 180) / 700).clamp(0.0, 1.0);
        foamFactor = (0.28 + 0.5 * verticality) * (0.55 + 0.65 * drop);
      case ImpactKind.floor:
        // Hitting the dry base is the classic foam disaster.
        foamFactor = 0.55 + 0.4 * (speed / 900).clamp(0.0, 1.0);
      case ImpactKind.spill:
      case ImpactKind.none:
        foamFactor = 0;
    }

    // A fat stream splashes more than a trickle.
    final intensity = (_flow / maxFlowRate).clamp(0.0, 1.0);
    foamFactor *= 0.65 + 0.5 * intensity;

    return StreamTrace(
      points: pts,
      impact: kind,
      impactPoint: hit,
      impactSpeed: speed,
      foamFactor: foamFactor.clamp(0.0, 0.95),
    );
  }

  static Offset? _segmentIntersect(Offset p1, Offset p2, Offset q1, Offset q2) {
    final r = p2 - p1;
    final s = q2 - q1;
    final denom = r.dx * s.dy - r.dy * s.dx;
    if (denom.abs() < 1e-9) return null;
    final qp = q1 - p1;
    final t = (qp.dx * s.dy - qp.dy * s.dx) / denom;
    final u = (qp.dx * r.dy - qp.dy * r.dx) / denom;
    if (t < 0 || t > 1 || u < 0 || u > 1) return null;
    return Offset(p1.dx + r.dx * t, p1.dy + r.dy * t);
  }
}
