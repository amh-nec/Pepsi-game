import 'package:flutter/services.dart';

/// Haptic feedback with built-in rate limiting, so the continuous pour ticks
/// never queue up on the platform channel.
class Haptics {
  bool enabled = true;

  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastWarn = DateTime.fromMillisecondsSinceEpoch(0);

  /// Light ticks while liquid is flowing. [intensity] 0..1 shortens the gap
  /// between ticks so a heavy pour feels heavier.
  void pourTick(double intensity) {
    if (!enabled) return;
    final gapMs = (150 - 80 * intensity.clamp(0.0, 1.0)).round();
    final now = DateTime.now();
    if (now.difference(_lastTick).inMilliseconds < gapMs) return;
    _lastTick = now;
    HapticFeedback.selectionClick();
  }

  /// Repeating warning thud as the glass approaches the rim.
  void warning() {
    if (!enabled) return;
    final now = DateTime.now();
    if (now.difference(_lastWarn).inMilliseconds < 320) return;
    _lastWarn = now;
    HapticFeedback.mediumImpact();
  }

  void success() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// Strong error buzz on overflow.
  Future<void> error() async {
    if (!enabled) return;
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.vibrate();
  }
}
