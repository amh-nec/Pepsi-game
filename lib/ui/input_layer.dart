import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../engine/game_controller.dart';

/// Translates touches (and optionally the accelerometer) into the normalised
/// inputs the controller expects. Keeping this separate means the simulation
/// never knows what a finger is.
class InputLayer extends StatefulWidget {
  const InputLayer({super.key, required this.game, required this.child});

  final GameController game;
  final Widget child;

  @override
  State<InputLayer> createState() => _InputLayerState();
}

class _InputLayerState extends State<InputLayer> {
  StreamSubscription<AccelerometerEvent>? _accel;
  double _tiltRaw = 0;

  @override
  void initState() {
    super.initState();
    _probeSensors();
  }

  /// Subscribe optimistically; if the platform has no accelerometer (or denies
  /// it) we simply stay in touch mode.
  void _probeSensors() {
    try {
      _accel = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 16),
      ).listen(
        (e) {
          if (!mounted) return;
          if (!widget.game.sensorAvailable) {
            setState(() => widget.game.sensorAvailable = true);
          }
          // Portrait: x is the left/right component of gravity (m/s^2).
          _tiltRaw = (-e.x / 9.81).clamp(-1.0, 1.0);
          if (widget.game.controlMode == ControlMode.tilt) {
            // Dead zone keeps a hand-held phone steady.
            final v = _tiltRaw.abs() < 0.06 ? 0.0 : _tiltRaw;
            widget.game.glassTiltInput = (v * 1.5).clamp(-1.0, 1.0);
          }
        },
        onError: (Object _) => _disableSensors(),
        cancelOnError: true,
      );
    } catch (_) {
      _disableSensors();
    }
  }

  void _disableSensors() {
    _accel?.cancel();
    _accel = null;
    if (!mounted) return;
    setState(() {
      widget.game.sensorAvailable = false;
      widget.game.setControlMode(ControlMode.touch);
    });
  }

  @override
  void dispose() {
    _accel?.cancel();
    super.dispose();
  }

  // ---- Gesture handling ---------------------------------------------------

  void _bottleDrag(Offset localPos, Size size, Offset delta) {
    final g = widget.game;
    g.bottleXInput = (localPos.dx / size.width).clamp(0.0, 1.0);
    // Dragging up tilts the bottle over; dragging down rights it.
    g.bottleTiltInput =
        (g.bottleTiltInput - delta.dy / (size.height * 0.45)).clamp(0.0, 1.0);
  }

  void _glassDrag(Offset delta, Size size) {
    final g = widget.game;
    g.glassTiltInput =
        (g.glassTiltInput + delta.dx / (size.width * 0.4)).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final tiltMode = widget.game.controlMode == ControlMode.tilt;
        return Stack(
          children: [
            widget.child,
            if (tiltMode)
              // One finger anywhere drives the bottle; the phone drives the glass.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (d) => _bottleDrag(d.localPosition, size, d.delta),
                  onPanEnd: (_) {},
                ),
              )
            else ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: size.width * 0.5,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (d) => _glassDrag(d.delta, size),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: size.width * 0.5,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (d) => _bottleDrag(
                    d.localPosition.translate(size.width * 0.5, 0),
                    size,
                    d.delta,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
