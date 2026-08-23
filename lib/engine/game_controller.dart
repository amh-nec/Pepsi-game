import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'audio.dart';
import 'effects.dart';
import 'geometry.dart';
import 'haptics.dart';
import 'physics.dart';

enum GamePhase { menu, playing, success, gameOver }

enum ControlMode { touch, tilt }

class RoundResult {
  const RoundResult({
    required this.score,
    required this.liquid,
    required this.foam,
    required this.timeUsed,
    required this.multiplier,
    required this.reason,
  });

  final int score;
  final double liquid;
  final double foam;
  final double timeUsed;
  final double multiplier;
  final String reason;
}

/// Owns the game loop, the round rules and every piece of mutable state the
/// UI needs. The physics itself lives in [PourPhysics]; this class only
/// decides *when* things happen.
class GameController extends ChangeNotifier {
  GameController({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_onTick);
  }

  static const double roundSeconds = 30;
  static const double targetLiquid = 0.90;
  static const double warnThreshold = 0.90;

  final GlassGeometry glass = GlassGeometry(
    center: Offset.zero,
    height: 260,
    topWidth: 150,
    bottomWidth: 118,
  );

  late final PourPhysics physics = PourPhysics(glass: glass);
  final Effects effects = Effects();
  final Haptics haptics = Haptics();
  final GameAudio audio = GameAudio();

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  GamePhase phase = GamePhase.menu;
  ControlMode controlMode = ControlMode.touch;
  bool sensorAvailable = false;

  double timeLeft = roundSeconds;
  int bestScore = 0;
  RoundResult? lastResult;

  /// Player input, both normalised to -1..1 / 0..1 by the input layer.
  double glassTiltInput = 0; // -1 .. 1
  double bottleTiltInput = 0; // 0 .. 1
  double bottleXInput = 0.5; // 0 .. 1 across the playfield

  double _bottleX = 0.5;
  double _bottleTilt = 0;
  double _glassTilt = 0;

  /// Cosmetic feedback state read by the painter.
  double shake = 0;
  double warnPulse = 0;
  Size viewport = Size.zero;

  bool get isWarning =>
      phase == GamePhase.playing && physics.total >= warnThreshold * physics.capacity;

  double get fillFraction => physics.total.clamp(0.0, 1.2);

  // ---- Lifecycle ----------------------------------------------------------

  Future<void> boot() async {
    await audio.init();
  }

  void layout(Size size, EdgeInsets padding) {
    viewport = size;
    final usableH = size.height - padding.top - padding.bottom;
    final h = (usableH * 0.34).clamp(180.0, 340.0);
    glass
      ..height = h
      ..topWidth = h * 0.58
      ..bottomWidth = h * 0.46
      ..center = Offset(size.width * 0.5, size.height - padding.bottom - usableH * 0.16);
    physics.bottleLength = h * 0.86;
  }

  void startRound() {
    physics.reset();
    effects.clear();
    timeLeft = roundSeconds;
    shake = 0;
    warnPulse = 0;
    glassTiltInput = 0;
    bottleTiltInput = 0;
    bottleXInput = 0.5;
    _bottleX = 0.5;
    _bottleTilt = 0;
    _glassTilt = 0;
    lastResult = null;
    phase = GamePhase.playing;
    _lastElapsed = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    notifyListeners();
  }

  void toMenu() {
    phase = GamePhase.menu;
    audio.stopAll();
    notifyListeners();
  }

  void setControlMode(ControlMode mode) {
    controlMode = mode;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    audio.dispose();
    super.dispose();
  }

  // ---- Loop ---------------------------------------------------------------

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // Clamp so a dropped frame or a resume from background never teleports
    // the simulation.
    dt = dt.clamp(0.0, 1 / 30);
    if (dt <= 0) return;

    if (phase == GamePhase.playing) {
      _stepPlaying(dt);
    } else {
      shake = approach(shake, 0, 6, dt);
      effects.update(dt, glass.surfaceYForFraction(physics.total));
      if (shake < 0.01 && effects.droplets.isEmpty) {
        _ticker.stop();
      }
    }
    notifyListeners();
  }

  void _stepPlaying(double dt) {
    // Smooth the raw input so both gyro jitter and finger jumps feel silky.
    _glassTilt = approach(_glassTilt, glassTiltInput * 0.62, 9, dt);
    _bottleTilt = approach(_bottleTilt, bottleTiltInput * 1.75, 10, dt);
    _bottleX = approach(_bottleX, bottleXInput, 12, dt);

    glass.tilt = _glassTilt;

    final w = viewport.width;
    physics
      ..bottleTilt = _bottleTilt
      ..bottlePos = Offset(
        lerpD(w * 0.16, w * 0.84, _bottleX.clamp(0.0, 1.0)),
        glass.center.dy - glass.height - viewport.height * 0.13,
      );

    physics.update(dt, active: true);

    _updateFeedback(dt);
    _updateEffects(dt);

    timeLeft -= dt;

    if (physics.isOverflowing) {
      _endRound(success: false, reason: 'OVERFLOW!');
      return;
    }
    if (physics.liquid >= targetLiquid && !physics.isPouring) {
      _endRound(success: true, reason: 'PERFECT POUR');
      return;
    }
    if (timeLeft <= 0) {
      timeLeft = 0;
      final ok = physics.liquid >= targetLiquid;
      _endRound(success: ok, reason: ok ? 'JUST IN TIME' : "TIME'S UP");
    }
  }

  void _updateFeedback(double dt) {
    final pouring = physics.isPouring;
    final intensity = (physics.flow / PourPhysics.maxFlowRate).clamp(0.0, 1.0);
    audio.setPouring(pouring, intensity: intensity);
    if (pouring) haptics.pourTick(intensity);

    if (isWarning) {
      warnPulse += dt * 7;
      shake = math.max(shake, 0.35);
      haptics.warning();
    } else {
      warnPulse = 0;
    }
    shake = approach(shake, 0, 5, dt);
  }

  void _updateEffects(double dt) {
    final surfaceY = glass.surfaceYForFraction(physics.total);
    final span = glass.spanAtY(surfaceY + 6);
    if (span != null && physics.liquid > 0.02) {
      effects.spawnBubbles(
        dt: dt,
        rate: 14 + 60 * physics.flow / PourPhysics.maxFlowRate,
        left: span.$1 + 6,
        right: span.$2 - 6,
        bottomY: glass.outline.maxY - 4,
        surfaceY: surfaceY,
      );
    }
    final trace = physics.trace;
    if (trace.impact == ImpactKind.liquid ||
        trace.impact == ImpactKind.floor ||
        trace.impact == ImpactKind.wall) {
      effects.splash(trace.impactPoint, trace.foamFactor * 1.2);
    }
    effects.update(dt, surfaceY);
  }

  void _endRound({required bool success, required String reason}) {
    audio.stopAll();
    final timeUsed = roundSeconds - timeLeft;
    final speedBonus = success
        ? (1.0 + (roundSeconds - timeUsed).clamp(0.0, roundSeconds) / roundSeconds)
        : 1.0;
    final purity = (1 - physics.foamRatio).clamp(0.0, 1.0);
    final precision = success ? 1.0 + purity * 1.5 : 0.4;
    final multiplier = speedBonus * precision;
    final base = success ? 1000 * physics.liquid.clamp(0.0, 1.0) : 250 * physics.liquid;
    final score = (base * multiplier).round();

    lastResult = RoundResult(
      score: score,
      liquid: physics.liquid,
      foam: physics.foam,
      timeUsed: timeUsed,
      multiplier: multiplier,
      reason: reason,
    );
    if (score > bestScore) bestScore = score;

    phase = success ? GamePhase.success : GamePhase.gameOver;
    if (success) {
      haptics.success();
      audio.success();
    } else {
      shake = 1.4;
      haptics.error();
      audio.fail();
    }
    notifyListeners();
  }
}
