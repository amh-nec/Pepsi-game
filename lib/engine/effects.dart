import 'dart:math' as math;
import 'dart:ui';

class Bubble {
  Bubble(this.pos, this.radius, this.speed, this.wobble, this.phase);
  Offset pos;
  double radius;
  double speed;
  double wobble;
  double phase;
  double life = 1;
}

class Droplet {
  Droplet(this.pos, this.vel, this.radius);
  Offset pos;
  Offset vel;
  double radius;
  double life = 1;
}

/// Purely cosmetic particle systems: fizzy bubbles inside the cola and
/// splash droplets at the impact point.
class Effects {
  Effects([int seed = 7]) : _rng = math.Random(seed);

  final math.Random _rng;
  final List<Bubble> bubbles = <Bubble>[];
  final List<Droplet> droplets = <Droplet>[];

  double _bubbleAcc = 0;

  void clear() {
    bubbles.clear();
    droplets.clear();
  }

  void spawnBubbles({
    required double dt,
    required double rate,
    required double left,
    required double right,
    required double bottomY,
    required double surfaceY,
  }) {
    if (right <= left || bottomY <= surfaceY) return;
    _bubbleAcc += rate * dt;
    while (_bubbleAcc >= 1) {
      _bubbleAcc -= 1;
      final x = lerp(left, right, _rng.nextDouble());
      final y = lerp(surfaceY, bottomY, 0.35 + _rng.nextDouble() * 0.65);
      bubbles.add(Bubble(
        Offset(x, y),
        1.2 + _rng.nextDouble() * 2.6,
        26 + _rng.nextDouble() * 52,
        3 + _rng.nextDouble() * 7,
        _rng.nextDouble() * math.pi * 2,
      ));
    }
    if (bubbles.length > 220) {
      bubbles.removeRange(0, bubbles.length - 220);
    }
  }

  void splash(Offset at, double strength) {
    final n = (strength * 3).round().clamp(0, 4);
    for (int i = 0; i < n; i++) {
      final a = -math.pi / 2 + (_rng.nextDouble() - 0.5) * 2.2;
      final sp = 60 + _rng.nextDouble() * 180 * strength;
      droplets.add(Droplet(
        at,
        Offset(math.cos(a) * sp, math.sin(a) * sp),
        1.2 + _rng.nextDouble() * 2.4,
      ));
    }
    if (droplets.length > 120) {
      droplets.removeRange(0, droplets.length - 120);
    }
  }

  void update(double dt, double surfaceY, {double gravity = 900}) {
    for (final b in bubbles) {
      b.phase += dt * b.wobble;
      b.pos = Offset(
        b.pos.dx + math.sin(b.phase) * 12 * dt,
        b.pos.dy - b.speed * dt,
      );
      if (b.pos.dy < surfaceY) b.life = 0;
    }
    bubbles.removeWhere((b) => b.life <= 0);

    for (final d in droplets) {
      d.vel = Offset(d.vel.dx, d.vel.dy + gravity * dt);
      d.pos = d.pos + d.vel * dt;
      d.life -= dt * 1.8;
    }
    droplets.removeWhere((d) => d.life <= 0);
  }

  static double lerp(double a, double b, double t) => a + (b - a) * t;
}
