import 'package:flutter/material.dart';

import '../engine/game_controller.dart';
import '../render/game_painter.dart';

/// Timer, fill gauge and foam gauge. Rebuilt from the controller each frame.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final p = game.physics;
    final liquid = p.liquid.clamp(0.0, 1.0);
    final foam = p.foam.clamp(0.0, 1.0);
    final urgent = game.timeLeft <= 6;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Chip(
                label: 'TIME',
                value: game.timeLeft.toStringAsFixed(1),
                color: urgent ? Palette.danger : Palette.accent,
              ),
              _Chip(
                label: 'TARGET',
                value: '${(GameController.targetLiquid * 100).round()}%',
                color: Colors.white70,
              ),
              _Chip(
                label: 'BEST',
                value: '${game.bestScore}',
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Gauge(
            liquid: liquid,
            foam: foam,
            capacity: p.capacity,
            warning: game.isWarning,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LIQUID ${(liquid * 100).toStringAsFixed(0)}%',
                  style: _small(Palette.colaLight)),
              Text('FOAM ${(foam * 100).toStringAsFixed(0)}%',
                  style: _small(game.isWarning ? Palette.danger : Palette.foamShade)),
            ],
          ),
        ],
      ),
    );
  }

  static TextStyle _small(Color c) => TextStyle(
        color: c,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              )),
          Text(value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              )),
        ],
      ),
    );
  }
}

/// Stacked bar: cola first, foam on top, target and rim markers overlaid.
class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.liquid,
    required this.foam,
    required this.capacity,
    required this.warning,
  });

  final double liquid;
  final double foam;
  final double capacity;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 18,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    Container(
                      width: w * liquid.clamp(0.0, 1.0),
                      decoration: const BoxDecoration(
                        color: Palette.colaLight,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(9),
                        ),
                      ),
                    ),
                    Container(
                      width: w * foam.clamp(0.0, 1.0 - liquid.clamp(0.0, 1.0)),
                      color: Palette.foam,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: w * GameController.targetLiquid - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Palette.accent),
              ),
              Positioned(
                left: (w * capacity - 2).clamp(0.0, w - 3),
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  color: warning ? Palette.danger : Colors.white54,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A compact reminder of the active control scheme.
class ControlHint extends StatelessWidget {
  const ControlHint({super.key, required this.mode});

  final ControlMode mode;

  @override
  Widget build(BuildContext context) {
    final text = mode == ControlMode.tilt
        ? 'TILT PHONE = GLASS   •   DRAG = BOTTLE'
        : 'LEFT DRAG = GLASS   •   RIGHT DRAG = BOTTLE';
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.35),
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Small helper used by the menu / result overlays.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
        decoration: BoxDecoration(
          color: primary ? Palette.accent : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: primary ? Palette.accent : Colors.white24,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? const Color(0xFF14243F) : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}
