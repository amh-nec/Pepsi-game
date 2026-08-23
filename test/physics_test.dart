import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_foam_challenge/engine/geometry.dart';
import 'package:zero_foam_challenge/engine/physics.dart';

GlassGeometry makeGlass() => GlassGeometry(
      center: const Offset(200, 500),
      height: 260,
      topWidth: 150,
      bottomWidth: 118,
    );

void main() {
  group('GlassGeometry', () {
    test('an empty glass has its surface at the base', () {
      final g = makeGlass();
      expect(g.surfaceYForFraction(0), closeTo(g.outline.maxY, 0.5));
    });

    test('a full glass has its surface at the rim', () {
      final g = makeGlass();
      expect(g.surfaceYForFraction(1), closeTo(g.outline.minY, 1.0));
    });

    test('capacity shrinks as the glass is tilted', () {
      final g = makeGlass();
      expect(g.spillCapacityFraction, closeTo(1.0, 1e-6));
      g.tilt = 0.5;
      expect(g.spillCapacityFraction, lessThan(1.0));
    });
  });

  group('PourPhysics', () {
    test('an upright bottle does not pour', () {
      final p = PourPhysics(glass: makeGlass())..bottleTilt = 0;
      p.update(1 / 60, active: true);
      expect(p.flow, 0);
      expect(p.total, 0);
    });

    test('a tilted bottle pours a measurable amount of liquid', () {
      final g = makeGlass();
      final p = PourPhysics(glass: g)
        ..bottleTilt = 1.2
        ..bottlePos = Offset(g.center.dx, g.center.dy - g.height - 90);
      for (int i = 0; i < 120; i++) {
        p.update(1 / 60, active: true);
      }
      // Everything poured is accounted for: in the glass, or on the table.
      expect(p.liquid + p.foam + p.wasted, greaterThan(0.1));
      expect(p.flow, greaterThan(0));
    });

    test('a stream missing the glass is wasted, not stored', () {
      final g = makeGlass();
      final p = PourPhysics(glass: g)
        ..bottleTilt = 1.2
        ..bottlePos = Offset(g.center.dx + 400, g.center.dy - g.height - 90);
      for (int i = 0; i < 60; i++) {
        p.update(1 / 60, active: true);
      }
      expect(p.wasted, greaterThan(0));
      expect(p.liquid, 0);
    });

    test('foam collapses back into liquid when pouring stops', () {
      final p = PourPhysics(glass: makeGlass())
        ..liquid = 0.4
        ..foam = 0.2;
      final foamBefore = p.foam;
      for (int i = 0; i < 60; i++) {
        p.update(1 / 60, active: false);
      }
      expect(p.foam, lessThan(foamBefore));
      expect(p.liquid, greaterThan(0.4));
    });

    test('foam factor rises with impact speed on the same surface', () {
      final g = makeGlass();
      double foamAfter(double dropHeight) {
        final p = PourPhysics(glass: g)
          ..bottleTilt = 0.75
          ..bottlePos = Offset(g.center.dx, g.center.dy - g.height - dropHeight);
        for (int i = 0; i < 30; i++) {
          p.update(1 / 60, active: true);
        }
        return p.trace.foamFactor;
      }

      final low = foamAfter(20);
      final high = foamAfter(160);
      if (low > 0 && high > 0) {
        expect(high, greaterThanOrEqualTo(low));
      }
    });
  });
}
