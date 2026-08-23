import 'package:flutter/material.dart';

import '../engine/game_controller.dart';
import '../render/game_painter.dart';
import 'hud.dart';

class MenuOverlay extends StatelessWidget {
  const MenuOverlay({super.key, required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return _Scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('THE ZERO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              )),
          const Text('FOAM CHALLENGE',
              style: TextStyle(
                color: Palette.accent,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              )),
          const SizedBox(height: 18),
          Text(
            'Pour down the tilted wall for a laminar,\n'
            'foam-free flow. Fill to '
            '${(GameController.targetLiquid * 100).round()}% before the timer '
            'runs out —\nand never let the glass overflow.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _ModeSwitch(game: game),
          const SizedBox(height: 24),
          PillButton(label: 'POUR', onTap: game.startRound),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    Widget option(ControlMode mode, String label, bool enabled) {
      final active = game.controlMode == mode;
      return Opacity(
        opacity: enabled ? 1 : 0.35,
        child: GestureDetector(
          onTap: enabled ? () => game.setControlMode(mode) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? Palette.accent.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? Palette.accent : Colors.white24,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active ? Palette.accent : Colors.white70,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(ControlMode.touch, 'TOUCH', true),
            const SizedBox(width: 10),
            option(ControlMode.tilt, 'TILT + TOUCH', game.sensorAvailable),
          ],
        ),
        if (!game.sensorAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No motion sensor detected — touch controls only',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}

class ResultOverlay extends StatelessWidget {
  const ResultOverlay({super.key, required this.game, required this.success});

  final GameController game;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final r = game.lastResult;
    return _Scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            success ? 'NICE POUR!' : 'ROUND OVER',
            style: TextStyle(
              color: success ? Palette.accent : Palette.danger,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          if (r != null) ...[
            const SizedBox(height: 6),
            Text(r.reason,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 20),
            Text('${r.score}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                )),
            const SizedBox(height: 12),
            _row('Liquid', '${(r.liquid * 100).toStringAsFixed(1)}%'),
            _row('Foam', '${(r.foam * 100).toStringAsFixed(1)}%'),
            _row('Time', '${r.timeUsed.toStringAsFixed(1)}s'),
            _row('Multiplier', '×${r.multiplier.toStringAsFixed(2)}'),
            _row('Best', '${game.bestScore}'),
          ],
          const SizedBox(height: 26),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PillButton(label: 'MENU', onTap: game.toMenu, primary: false),
              const SizedBox(width: 12),
              PillButton(label: 'RETRY', onTap: game.startRound),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: SizedBox(
          width: 220,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
              Text(value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
        ),
      );
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC050B15),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: child,
      ),
    );
  }
}
